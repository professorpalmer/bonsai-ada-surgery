"""Saved conversations on disk for the Bonsai layer (#138 T1-c): restore a long prompt in seconds instead of reading it again.

The server (llama-server -np 1 --slot-save-path DIR) can write its one slot (KV cache + the GDN / conv states, and with
patches 0062 / 0063 the draft context in a <file>.draft sidecar) to a file and read it back. A request whose tokens EXTEND
the restored tokens then reads only its new tokens (4070 T1-b: 245k in 2.2 s instead of 468 s, answers byte-identical). A
request that diverges inside the restored tokens reads everything again: the 48 GDN layers keep a recurrent state that cannot
roll back without a checkpoint, and checkpoints are not in the file.

So the save point is the END OF THE LAST MESSAGE (before the generation prompt): before a long request is answered, a
prefill-only call (/completion with those exact tokens, n_predict 0) fills the slot, the slot is saved, and then the real
request runs and reads ~nothing. The next turn of the same conversation (prompt + rendered answer + new turn) always extends
that saved state, also when the template drops the reasoning from the history. Before each request the layer restores the
longest saved token prefix when it is longer than what the server holds now: after a restart, or when two or more long
conversations alternate. At a turn that saves again, the new tokens are processed in other batch splits than in memory, so
greedy output can differ by a token there (P160 turn 4); restore-only turns are identical.

Off unless BONSAI_SLOT_SAVE_PATH is set (the same folder as the server's --slot-save-path). Settings:
  BONSAI_SLOT_CACHE_MIN   prompt tokens for a request to take part (default 16384)
  BONSAI_SLOT_CACHE_GROW  save again only when the prompt grew by this many tokens since the best saved prefix (8192)
  BONSAI_SLOT_CACHE_GB    disk budget, oldest-used files removed first (20)
  BONSAI_SLOT_CACHE_GAIN  restore only when it saves at least this many tokens of reading (2048)
Requests with images (any non-text content part) do not take part: /tokenize cannot reproduce the image chunks.
Read ahead (T1-d): a chat request with "prefill_only": true reads and saves its prompt and returns no text; the later real
request then restores it.
Any failure here only logs and lets the request run as before.
"""
import array
import hashlib
import json
import os
import re
import sys
import threading
import time
import urllib.request

# Request fields that do NOT change the rendered prompt; everything else goes to /apply-template (reasoning_effort,
# continue_final_message, chat_template_kwargs, tools ... all can change it; review B2).
NOT_TEMPLATE = {"stream", "stream_options", "temperature", "top_p", "top_k", "min_p", "typical_p", "max_tokens",
                "max_completion_tokens", "n_predict", "seed", "presence_penalty", "frequency_penalty", "repeat_penalty",
                "logit_bias", "logprobs", "top_logprobs", "stop", "n", "user", "cache_prompt", "id_slot", "samplers",
                "mirostat", "mirostat_tau", "mirostat_eta", "dry_multiplier", "dry_base", "dry_allowed_length",
                "xtc_probability", "xtc_threshold", "timings_per_token", "return_progress", "metadata", "store"}
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
PREFIX = "lc-"   # every file the cache writes starts with this, so the cleanup never touches a user's own slot files (review R2)


def _sha(tokens):
    return hashlib.sha256(array.array("I", tokens).tobytes()).hexdigest()


def has_media(body):
    """True when any message has a non-text content part (image, audio, file): the cache skips such requests (review B3)."""
    for m in body.get("messages") or []:
        c = m.get("content")
        if isinstance(c, list) and any(isinstance(p, dict) and p.get("type") not in (None, "text") for p in c):
            return True
    return False


class SlotCache:
    def __init__(self, upstream, folder, min_tokens=16384, grow=8192, budget_gb=20.0, log=None, min_gain=2048):
        self.upstream, self.folder = upstream.rstrip("/"), os.path.abspath(folder)
        self.min_gain = int(min_gain)   # restore only when it saves at least this many tokens of reading (~15-25 s at depth)
        self.min_tokens, self.grow, self.budget = int(min_tokens), int(grow), float(budget_gb) * 2**30
        self.log = log or (lambda *a: sys.stderr.write("[slots] " + " ".join(str(x) for x in a) + "\n"))
        # the server has one slot: check / restore / save / answer run one at a time; re-entrant so that a send inside a
        # locked loop (the interpreter stream) does not deadlock
        self.lock = threading.RLock()
        self.held = []                 # tokens the server's slot is known to start with
        os.makedirs(self.folder, exist_ok=True)
        self.index_path = os.path.join(self.folder, PREFIX + "index.jsonl")
        self.index = {}                # sha -> {"n": tokens, "last": time, "bytes": size}
        self._load_index()
        self._clean()

    @classmethod
    def from_env(cls, upstream, log=None):
        """The cache from the environment, or None when it is off or cannot start (a bad value, a folder that cannot be
        made): the layer then runs without it (review N1)."""
        folder = os.environ.get("BONSAI_SLOT_SAVE_PATH")
        if not folder:
            return None
        try:
            return cls(upstream, folder, int(os.environ.get("BONSAI_SLOT_CACHE_MIN", 16384)),
                       int(os.environ.get("BONSAI_SLOT_CACHE_GROW", 8192)), float(os.environ.get("BONSAI_SLOT_CACHE_GB", 20)),
                       log, int(os.environ.get("BONSAI_SLOT_CACHE_GAIN", 2048)))
        except Exception as e:
            (log or (lambda *a: sys.stderr.write("[slots] " + " ".join(str(x) for x in a) + "\n")))(
                "saved conversations OFF: cannot start the cache:", repr(e))
            return None

    # ---- files and index --------------------------------------------------------------------------------------
    @staticmethod
    def _name(sha):
        return PREFIX + sha + ".bin"

    def _bin(self, sha):
        return os.path.join(self.folder, self._name(sha))

    def _files(self, sha):
        b = self._bin(sha)
        return (b, b + ".draft", os.path.join(self.folder, PREFIX + sha + ".tok"))

    def _load_index(self):
        try:
            lines = open(self.index_path, encoding="utf-8").read().splitlines()
        except FileNotFoundError:
            return
        except Exception as e:
            self.log("index read failed:", repr(e))
            return
        for line in lines:   # one bad line loses that line only (review N8)
            try:
                e = json.loads(line)
                sha = e["sha"]
                if not SHA_RE.match(sha):
                    continue
                if e.get("drop"):
                    self.index.pop(sha, None)
                elif os.path.exists(self._bin(sha)):
                    self.index[sha] = {"n": int(e["n"]), "last": float(e["last"]), "bytes": int(e["bytes"])}
            except Exception:
                continue

    def _clean(self):
        """Remove crash leftovers (lc-saving-* files) and cache files that the index does not list (review N8). Only files
        with the cache's own prefix (lc-) are touched: the folder is also the server's --slot-save-path (review R2)."""
        try:
            for f in os.listdir(self.folder):
                if not f.startswith(PREFIX) or f == PREFIX + "index.jsonl":
                    continue
                p = os.path.join(self.folder, f)
                stem = f[len(PREFIX):].split(".", 1)[0]
                if f.startswith(PREFIX + "saving-") or (SHA_RE.match(stem) and stem not in self.index):
                    try:
                        os.remove(p)
                    except OSError:
                        pass
        except Exception as e:
            self.log("clean failed:", repr(e))

    def _note(self, entry):
        with open(self.index_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")

    def _evict(self):
        total = sum(e["bytes"] for e in self.index.values())
        for sha, e in sorted(self.index.items(), key=lambda kv: kv[1]["last"]):
            if total <= self.budget:
                break
            ok = True
            for p in self._files(sha):
                try:
                    if os.path.exists(p):
                        os.remove(p)
                except OSError:
                    ok = False
            if not ok:   # keep the entry when a file could not be removed (review N8)
                continue
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
        b = {k: v for k, v in body.items() if k not in NOT_TEMPLATE}
        toks = self._tokens(b, auth)
        base = self._tokens({**b, "add_generation_prompt": False}, auth)
        if len(base) > len(toks) or toks[:len(base)] != base:
            base = toks   # the template renders the last message differently without the generation prompt
        return toks, base

    # ---- the hook ---------------------------------------------------------------------------------------------
    def before(self, body, auth, force_save=False):
        """Call with the lock held, right before the request goes to the server. Restores and / or saves as needed.
        force_save (read ahead, T1-d): nothing is sent after this call, so "held" only changes when a prefill-only call ran;
        it saves the first state of a conversation at any size >= BONSAI_SLOT_CACHE_MIN and a longer one only after
        BONSAI_SLOT_CACHE_GROW more tokens (no new multi-GB file per turn). info["status"] says what happened."""
        t0 = time.time()
        if has_media(body):
            if not force_save:
                self.held = []
            return {"slot_cache": "skipped (media)", "status": "skipped: media"}
        try:
            toks, base = self.prompt_tokens(body, auth)
        except Exception as e:
            self.log("tokenize failed, cache skipped:", repr(e))
            if not force_save:
                self.held = []
            return {"slot_cache": "skipped", "status": "failed: tokenize " + repr(e)[:200]}
        info = {"slot_cache_tokens": len(toks)}
        if len(toks) < self.min_tokens:
            if not force_save:
                self.held = toks
            info["status"] = "skipped: short (< %d tokens)" % self.min_tokens
            return info
        common = 0
        for a, b in zip(self.held, toks):
            if a != b:
                break
            common += 1
        best_sha, best_n = None, 0
        for sha, e in self.index.items():
            n = e["n"]
            # strictly shorter than the request: a state equal to the whole request would need a 1-token rollback (review N9)
            if best_n < n < len(toks) and _sha(toks[:n]) == sha:
                best_sha, best_n = sha, n
        if best_sha and best_n >= common + self.min_gain:
            try:
                t1 = time.time()
                self._post("/slots/0?action=restore", {"filename": self._name(best_sha)}, auth)
                self.index[best_sha]["last"] = time.time()
                self._note({"sha": best_sha, **self.index[best_sha]})
                common = best_n
                info["slot_cache_restored"] = best_n
                info["slot_cache_restore_s"] = round(time.time() - t1, 2)
                self.log("restored", best_sha[:12], best_n, "tokens in", info["slot_cache_restore_s"], "s")
            except Exception as e:
                self.log("restore failed:", repr(e))
        need = (1 if best_n == 0 else self.grow) if force_save else self.grow
        if len(base) < len(toks) and len(base) - max(best_n, 0) >= need:
            tmp = PREFIX + "saving-%d.bin" % os.getpid()
            try:
                for p in (tmp, tmp + ".draft"):   # a stale sidecar from a crashed save must not be renamed with this one
                    try:
                        os.remove(os.path.join(self.folder, p))
                    except OSError:
                        pass
                t1 = time.time()
                self._post("/completion", {"prompt": base, "n_predict": 0, "cache_prompt": True}, auth)
                t2 = time.time()
                r = self._post("/slots/0?action=save", {"filename": tmp}, auth)
                n = int(r.get("n_saved") or len(base))
                saved = base[:n] if n <= len(base) else base   # the server may hold back the last token
                sha = _sha(saved)
                os.replace(os.path.join(self.folder, tmp), self._bin(sha))
                if os.path.exists(os.path.join(self.folder, tmp + ".draft")):   # the draft sidecar goes with it (review B1)
                    os.replace(os.path.join(self.folder, tmp + ".draft"), self._bin(sha) + ".draft")
                with open(self._files(sha)[2], "wb") as f:
                    array.array("I", saved).tofile(f)
                size = sum(os.path.getsize(p) for p in self._files(sha) if os.path.exists(p))
                self.index[sha] = {"n": len(saved), "last": time.time(), "bytes": size}
                self._note({"sha": sha, **self.index[sha]})
                info["slot_cache_saved"] = len(saved)
                info["slot_cache_gen_prompt_tokens"] = len(toks) - len(base)
                info["slot_cache_prefill_s"] = round(t2 - t1, 2)
                info["slot_cache_save_s"] = round(time.time() - t2, 2)
                info["status"] = "saved"
                self.log("saved", sha[:12], len(saved), "tokens: prefill", info["slot_cache_prefill_s"], "s, save", info["slot_cache_save_s"], "s")
                self._evict()
            except Exception as e:
                self.log("save failed:", repr(e))
                info["status"] = "failed: save " + repr(e)[:200]
        if "status" not in info:
            if info.get("slot_cache_restored"):
                info["status"] = "restored"
            elif len(base) > max(best_n, 0):
                info["status"] = "skipped: growth < %d" % need
            else:
                info["status"] = "skipped: no new tokens to save"
        if force_save:   # only the work done here changed the server's slot
            if info.get("slot_cache_saved"):
                self.held = base
            elif info.get("slot_cache_restored"):
                self.held = toks[:info["slot_cache_restored"]]   # a restore-only read-ahead (re-review: blocking)
        else:
            self.held = toks
        info["slot_cache_s"] = round(time.time() - t0, 2)
        return info
