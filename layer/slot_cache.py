"""Saved conversations on disk for the Bonsai layer (#138 T1-c): restore a long prompt in seconds instead of reading it again.

The server (llama-server -np 1 --slot-save-path DIR) can write its one slot (KV cache + the GDN / conv states) to a file and
read it back. A request whose tokens EXTEND the restored tokens then reads only its new tokens (4070 T1-b: 245k in 2.2 s
instead of 468 s, answers byte-identical). A request that diverges inside the restored tokens reads everything again: the
48 GDN layers keep a recurrent state that cannot roll back without a checkpoint, and checkpoints are not in the file.

So the save point is the END OF THE LAST MESSAGE (before the generation prompt): before a long request is answered, a
prefill-only call (/completion with those exact tokens, n_predict 0) fills the slot, the slot is saved, and then the real request runs and reads ~nothing.
The next turn of the same conversation (prompt + rendered answer + new turn) always extends that saved state, also when
the template drops the reasoning from the history. Before each request the layer restores the longest saved token prefix
when it is longer than what the server holds now: after a restart, or when two or more long conversations alternate.

Off unless BONSAI_SLOT_SAVE_PATH is set (the same folder as the server's --slot-save-path). Settings:
  BONSAI_SLOT_CACHE_MIN   prompt tokens for a request to take part (default 16384)
  BONSAI_SLOT_CACHE_GROW  save again only when the prompt grew by this many tokens since the best saved prefix (8192)
  BONSAI_SLOT_CACHE_GB    disk budget, oldest-used files removed first (20)
  BONSAI_SLOT_CACHE_GAIN  restore only when it saves at least this many tokens of reading (2048)
Any failure here only logs and lets the request run as before.
"""
import array
import hashlib
import json
import os
import sys
import threading
import time
import urllib.request

# Request fields that change the rendered prompt. Everything else (sampling, stream, max_tokens) does not.
TEMPLATE_KEYS = ("messages", "tools", "tool_choice", "parallel_tool_calls", "chat_template_kwargs", "reasoning_format",
                 "response_format", "add_generation_prompt")


def _sha(tokens):
    return hashlib.sha256(array.array("I", tokens).tobytes()).hexdigest()


class SlotCache:
    def __init__(self, upstream, folder, min_tokens=16384, grow=8192, budget_gb=20.0, log=None, min_gain=2048):
        self.upstream, self.folder = upstream.rstrip("/"), folder
        self.min_gain = int(min_gain)   # restore only when it saves at least this many tokens of reading (~15-25 s at depth)
        self.min_tokens, self.grow, self.budget = int(min_tokens), int(grow), float(budget_gb) * 2**30
        self.log = log or (lambda *a: sys.stderr.write("[slots] " + " ".join(str(x) for x in a) + "\n"))
        self.lock = threading.Lock()   # the server has one slot: check / restore / save / answer run one at a time
        self.held = []                 # tokens the server's slot is known to start with
        os.makedirs(folder, exist_ok=True)
        self.index_path = os.path.join(folder, "index.jsonl")
        self.index = {}                # sha -> {"n": tokens, "last": time, "bytes": size}
        self._load_index()

    @classmethod
    def from_env(cls, upstream, log=None):
        folder = os.environ.get("BONSAI_SLOT_SAVE_PATH")
        if not folder:
            return None
        return cls(upstream, folder, os.environ.get("BONSAI_SLOT_CACHE_MIN", 16384),
                   os.environ.get("BONSAI_SLOT_CACHE_GROW", 8192), os.environ.get("BONSAI_SLOT_CACHE_GB", 20), log,
                   os.environ.get("BONSAI_SLOT_CACHE_GAIN", 2048))

    # ---- index ------------------------------------------------------------------------------------------------
    def _load_index(self):
        try:
            for line in open(self.index_path, encoding="utf-8"):
                e = json.loads(line)
                if e.get("drop"):
                    self.index.pop(e["sha"], None)
                elif os.path.exists(self._bin(e["sha"])):
                    self.index[e["sha"]] = {"n": e["n"], "last": e["last"], "bytes": e["bytes"]}
        except FileNotFoundError:
            pass
        except Exception as e:   # a damaged index only loses the cache, never the request
            self.log("index read failed:", repr(e))

    def _note(self, entry):
        with open(self.index_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")

    def _bin(self, sha):
        return os.path.join(self.folder, sha + ".bin")

    def _tok(self, sha):
        return os.path.join(self.folder, sha + ".tok")

    def _evict(self):
        total = sum(e["bytes"] for e in self.index.values())
        for sha, e in sorted(self.index.items(), key=lambda kv: kv[1]["last"]):
            if total <= self.budget:
                break
            for p in (self._bin(sha), self._tok(sha)):
                try:
                    os.remove(p)
                except OSError:
                    pass
            total -= e["bytes"]
            del self.index[sha]
            self._note({"sha": sha, "drop": True})
            self.log("evicted", sha[:12], e["n"], "tokens")

    # ---- server calls -----------------------------------------------------------------------------------------
    def _post(self, path, body, auth, timeout=7200):
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = auth
        req = urllib.request.Request(self.upstream + path, data=json.dumps(body).encode(), headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read() or b"{}")

    def _tokens(self, b, auth):
        prompt = self._post("/apply-template", b, auth)["prompt"]
        return self._post("/tokenize", {"content": prompt, "add_special": False, "parse_special": True}, auth)["tokens"]

    def prompt_tokens(self, body, auth):
        """(tokens of the full prompt, tokens up to the end of the last message). The second one stops before the
        generation prompt (<|im_start|>assistant ... <think>): the next turn renders the previous answer from the history,
        and with thinking on the template drops the reasoning, so the generation-prompt tokens can differ there (4070
        review of T1-c). A state saved at the end of the last message is a prefix of every later turn."""
        b = {k: body[k] for k in TEMPLATE_KEYS if k in body}
        toks = self._tokens(b, auth)
        base = self._tokens({**b, "add_generation_prompt": False}, auth)
        if len(base) > len(toks) or toks[:len(base)] != base:
            base = toks   # the template renders the last message differently without the generation prompt
        return toks, base

    # ---- the two hooks ----------------------------------------------------------------------------------------
    def before(self, body, auth):
        """Call with the lock held, right before the request goes to the server. Restores and / or saves as needed."""
        t0 = time.time()
        try:
            toks, base = self.prompt_tokens(body, auth)
        except Exception as e:
            self.log("tokenize failed, cache skipped:", repr(e))
            self.held = []
            return {"slot_cache": "skipped"}
        info = {"slot_cache_tokens": len(toks)}
        if len(toks) < self.min_tokens:
            self.held = toks
            return info
        common = 0
        for a, b in zip(self.held, toks):
            if a != b:
                break
            common += 1
        best_sha, best_n = None, 0
        for sha, e in self.index.items():
            n = e["n"]
            if best_n < n <= len(toks) and _sha(toks[:n]) == sha:
                best_sha, best_n = sha, n
        if best_sha and best_n >= common + self.min_gain:
            try:
                t1 = time.time()
                self._post("/slots/0?action=restore", {"filename": best_sha + ".bin"}, auth)
                self.index[best_sha]["last"] = time.time()
                self._note({"sha": best_sha, "n": best_n, "last": self.index[best_sha]["last"], "bytes": self.index[best_sha]["bytes"]})
                common = best_n
                info["slot_cache_restored"] = best_n
                info["slot_cache_restore_s"] = round(time.time() - t1, 2)
                self.log("restored", best_sha[:12], best_n, "tokens in", info["slot_cache_restore_s"], "s")
            except Exception as e:
                self.log("restore failed:", repr(e))
        if len(base) - max(best_n, 0) >= self.grow:
            try:
                t1 = time.time()
                self._post("/completion", {"prompt": base, "n_predict": 0, "cache_prompt": True}, auth)
                t2 = time.time()
                tmp = "saving-%d.bin" % os.getpid()
                r = self._post("/slots/0?action=save", {"filename": tmp}, auth)
                n = int(r.get("n_saved") or len(base))
                saved = base[:n] if n <= len(base) else base   # the server may hold back the last token
                sha = _sha(saved)
                os.replace(os.path.join(self.folder, tmp), self._bin(sha))
                with open(self._tok(sha), "wb") as f:
                    array.array("I", saved).tofile(f)
                size = os.path.getsize(self._bin(sha))
                self.index[sha] = {"n": len(saved), "last": time.time(), "bytes": size + 4 * len(saved)}
                self._note({"sha": sha, **self.index[sha]})
                info["slot_cache_saved"] = len(saved)
                info["slot_cache_gen_prompt_tokens"] = len(toks) - len(base)
                info["slot_cache_prefill_s"] = round(t2 - t1, 2)
                info["slot_cache_save_s"] = round(time.time() - t2, 2)
                self.log("saved", sha[:12], len(saved), "tokens: prefill", info["slot_cache_prefill_s"], "s, save", info["slot_cache_save_s"], "s")
                self._evict()
            except Exception as e:
                self.log("save failed:", repr(e))
        self.held = toks
        info["slot_cache_s"] = round(time.time() - t0, 2)
        return info
