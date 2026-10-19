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
  BONSAI_SLOT_CACHE_AFTER save after the answer (default 1; 0 turns it off): see below
Requests with images (any non-text content part) do not take part: /tokenize cannot reproduce the image chunks.
Save after the answer (on by default since run 8 of docs/research/save-after-answer-20261018): when the next turn of a conversation renders the previous answer with the
same tokens the model generated (thinking off, or a client that sends the reasoning back; not when the template or the
client drops or rewrites it), the state right after the answer is a prefix of the next turn. After each answer the layer
reads the slot's token count (GET /slots); at the next turn of the same conversation the cached-token count in the
server's reply (timings.cache_n) tells whether that state was a prefix (no file is written for this test). When it was, the conversation saves after the answer
instead of before the request: no prefill-only call (the answer is computed as without the cache), and the save runs after
the client has the answer. The saved tokens come from the slot file's own header, so a restore is exact. When the test
fails (the client dropped the reasoning, edited a turn, ...), the conversation goes back to the save before the request.
The result per conversation is kept on disk (lc-conv.json), so a restarted layer keeps it. A stop of the server within
seconds of an answer can lose that save; the next restore then uses the save before it.
Delta saves (a server that reports "slot_save_delta" in /props; BONSAI_SLOT_CACHE_CHAIN, default 8, 0 = off): a save
(after the answer, or before the request) that continues an earlier save of the conversation writes only the cells after it ("pos_min"), a few
thousand tokens instead of the whole conversation. A restore loads the chain: the full save, then each delta
("append"). After BONSAI_SLOT_CACHE_CHAIN deltas (8) the layer writes a full save of the conversation the next time it
has been idle for BONSAI_SLOT_CACHE_IDLE seconds (30; a full save can take minutes on a slow drive, and the user does
not wait for it then); after BONSAI_SLOT_CACHE_CHAIN_MAX deltas (32) the next save is full in any case. Eviction removes
whole chains.
Every answer (a delta server, BONSAI_SLOT_CACHE_EVERY=1, the default): the layer saves after every answer of a long
conversation, as a delta, so a restore lands exactly on the last answer and the next request reads only the new turn:
the same computation as a session that never left memory, also when several conversations take turns. The test is
exact: at the next turn of the conversation, its last save after an answer must be a token prefix of the new prompt.
When it is not (the template or the client rewrites the answer), the conversation goes back to the save before the
request. Without delta support the cached-token test above is used.
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


GGSQ = 0x67677371   # LLAMA_FILE_MAGIC_GGSQ: llama_state_seq_save_file writes magic, version 2, token count, tokens, state


def read_tokens(path):
    """The token list at the head of a slot file: exactly the tokens whose state the file holds. The server writes its
    server_tokens state there: LLAMA_TOKEN_NULL (0xffffffff), state version 1, the token count, the tokens, then the
    media-chunk count (0 for text). An older server wrote the plain token list."""
    with open(path, "rb") as f:
        head = array.array("I")
        head.fromfile(f, 3)
        if head[0] != GGSQ or head[1] != 2:
            raise ValueError("not a version-2 slot file: magic %08x version %d" % (head[0], head[1]))
        packed = array.array("I")
        packed.fromfile(f, head[2])
    if not packed or packed[0] != 0xFFFFFFFF:
        return list(packed)
    if len(packed) < 4 or packed[1] != 1 or packed[2] + 4 > len(packed):
        raise ValueError("unknown server_tokens state in the slot file")
    n = packed[2]
    if packed[3 + n] != 0:
        raise ValueError("the slot holds media chunks")
    return list(packed[3:3 + n])


def has_media(body):
    """True when any message has a non-text content part (image, audio, file): the cache skips such requests (review B3)."""
    for m in body.get("messages") or []:
        c = m.get("content")
        if isinstance(c, list) and any(isinstance(p, dict) and p.get("type") not in (None, "text") for p in c):
            return True
    return False


class SlotCache:
    def __init__(self, upstream, folder, min_tokens=16384, grow=8192, budget_gb=20.0, log=None, min_gain=2048, after=False,
                 chain=0, chain_max=None, idle_s=30.0, every=True):
        self.upstream, self.folder = upstream.rstrip("/"), os.path.abspath(folder)
        self.after_on = bool(after)   # save after the answer when the conversation passed the prefix test (see the top)
        self.chain = int(chain)        # delta saves: a full save when idle after this many deltas (0: deltas off)
        self.chain_max = int(chain_max) if chain_max is not None else 4 * self.chain   # ... and in any case after this many
        self.idle_s = float(idle_s)    # the idle time before a full save of a long chain
        self.every = bool(every)       # with a delta server: save after every answer, test by exact token match
        self.last_after = {}           # conversation key -> sha of its last save after an answer
        self.compact = None            # (conversation key, auth) of a chain that wants a full save when idle
        self.t_active = time.time()    # the end of the last chat request
        self.delta_ok = None           # the server takes "pos_min" / "append" (GET /props slot_save_delta); None: not asked
        self.min_gain = int(min_gain)   # restore only when it saves at least this many tokens of reading (~15-25 s at depth)
        self.min_tokens, self.grow, self.budget = int(min_tokens), int(grow), float(budget_gb) * 2**30
        self.log = log or (lambda *a: sys.stderr.write("[slots] " + " ".join(str(x) for x in a) + "\n"))
        # the server has one slot: check / restore / save / answer run one at a time; re-entrant so that a send inside a
        # locked loop (the interpreter stream) does not deadlock
        self.lock = threading.RLock()
        self.held = []                 # tokens the server's slot is known to start with
        self.last = None               # the last request's tokens etc., for after() (save after the answer)
        self.probe = None              # (conversation, slot token count after its last answer): the prefix test
        self.wait = None               # the same, armed by before(): the next reply's cached count resolves it
        self.busy_n = 0                # chat requests between their start and the end of after(): a stop now can lose a save
        self.busy_lock = threading.Lock()
        os.makedirs(self.folder, exist_ok=True)
        self.conv_path = os.path.join(self.folder, PREFIX + "conv.json")
        self.conv = {}                 # conversation key -> True / False: the last prefix test passed / failed
        try:
            self.conv = {k: bool(v) for k, v in json.load(open(self.conv_path, encoding="utf-8")).items()}
        except FileNotFoundError:
            pass
        except Exception as e:
            self.log("conv read failed:", repr(e))
        self.index_path = os.path.join(self.folder, PREFIX + "index.jsonl")
        self.index = {}                # sha -> {"n": tokens, "last": time, "bytes": size}
        self._load_index()
        self._clean()
        if self.chain > 0:
            threading.Thread(target=self._idle_loop, daemon=True).start()

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
                       log, int(os.environ.get("BONSAI_SLOT_CACHE_GAIN", 2048)),
                       os.environ.get("BONSAI_SLOT_CACHE_AFTER", "1") not in ("", "0"),
                       int(os.environ.get("BONSAI_SLOT_CACHE_CHAIN", 8)),
                       int(os.environ["BONSAI_SLOT_CACHE_CHAIN_MAX"]) if os.environ.get("BONSAI_SLOT_CACHE_CHAIN_MAX") else None,
                       float(os.environ.get("BONSAI_SLOT_CACHE_IDLE", 30)),
                       os.environ.get("BONSAI_SLOT_CACHE_EVERY", "1") not in ("", "0"))
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
                    self.index[sha] = {"n": int(e["n"]), "last": float(e["last"]), "bytes": int(e["bytes"]),
                                       "parent": e.get("parent"), "depth": int(e.get("depth") or 0)}
            except Exception:
                continue
        # a delta whose chain lost a file is no use: drop it (its files go in _clean)
        changed = True
        while changed:
            changed = False
            for sha, e in list(self.index.items()):
                if e.get("parent") and e["parent"] not in self.index:
                    del self.index[sha]
                    changed = True

    def enter(self):
        with self.busy_lock:
            self.busy_n += 1

    def leave(self):
        with self.busy_lock:
            self.busy_n = max(0, self.busy_n - 1)
            self.t_active = time.time()

    def _idle_loop(self):
        while True:
            time.sleep(max(1.0, min(5.0, self.idle_s / 4)))
            try:
                self.idle_tick()
            except Exception as e:   # never stop the thread
                self.log("idle full save failed:", repr(e))

    def idle_tick(self, now=None):
        """The full save of a long chain, when the layer has been idle for idle_s. Returns the info dict or None."""
        now = time.time() if now is None else now
        if not self.compact or self.busy or now - self.t_active < self.idle_s:
            return None
        if not self.lock.acquire(blocking=False):
            return None
        if not self.compact or self.busy:   # review: a request may have started between the check and the lock
            self.lock.release()
            return None
        self.enter()
        try:
            key, auth = self.compact
            self.compact = None
            tmp = self._tmp()
            t1 = time.time()
            self._post("/slots/0?action=save", {"filename": tmp}, auth)
            saved = read_tokens(os.path.join(self.folder, tmp))
            if len(saved) < self.min_tokens or self._conv_key(saved) != key:   # the slot holds another conversation now
                for f in (tmp, tmp + ".draft"):
                    try:
                        os.remove(os.path.join(self.folder, f))
                    except OSError:
                        pass
                self.log("idle full save skipped: the slot holds another conversation")
                return {"skipped": True}
            tip = self.last_after.get(key)
            old_chain = self._chain(tip) if tip in self.index else None
            tipn = self.index[tip]["n"] if old_chain else 0
            tipt = self._toks_of(tip) if old_chain else []
            sha, size = self._store(tmp, saved)
            if old_chain and (tip == sha or saved[:tipn] == tipt):   # the full save holds every token of the old chain
                self._drop([x for x in old_chain if x != sha], "replaced (idle full save)")
            self.last_after[key] = sha
            self.held = saved
            info = {"saved": len(saved), "save_s": round(time.time() - t1, 2)}
            self.log("idle full save", sha[:12], len(saved), "tokens:", info["save_s"], "s")
            self._evict()
            return info
        finally:
            self.leave()
            self.lock.release()

    @property
    def busy(self):
        return self.busy_n > 0

    def _conv_key(self, toks):
        """A conversation is its first BONSAI_SLOT_CACHE_MIN tokens (they do not change from turn to turn). Two
        conversations with the same start share the prefix-test result only; a restore always checks the exact tokens."""
        return _sha(toks[:self.min_tokens])[:24]

    def _set_conv(self, key, ok):
        if self.conv.get(key) is ok:
            return
        self.conv.pop(key, None)
        self.conv[key] = ok
        if len(self.conv) > 1000:   # keep the file small: drop the oldest entries (dicts keep insertion order)
            for k in list(self.conv)[:len(self.conv) - 1000]:
                del self.conv[k]
        try:
            tmp = self.conv_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.conv, f)
            os.replace(tmp, self.conv_path)
        except Exception as e:
            self.log("conv write failed:", repr(e))

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

    def _chain(self, sha):
        """[full save, delta, ..., sha] for an index entry, or None when a link is missing."""
        out = []
        while sha:
            e = self.index.get(sha)
            if e is None or len(out) > 1000:
                return None
            out.append(sha)
            sha = e.get("parent")
        return out[::-1]

    def _root(self, sha):
        c = self._chain(sha)
        return c[0] if c else sha

    def _drop(self, shas, why):
        """Remove these saves (files and index entries), deepest first, so no delta is left without its parent."""
        for sha in sorted(shas, key=lambda x: -self.index.get(x, {"depth": 0})["depth"]):
            if sha not in self.index:
                continue
            if any(e.get("parent") == sha for k, e in self.index.items() if k not in shas):
                continue   # another save still builds on it
            for f in self._files(sha):
                try:
                    if os.path.exists(f):
                        os.remove(f)
                except OSError:
                    pass
            e = self.index.pop(sha)
            self._note({"sha": sha, "drop": True})
            self.log(why, sha[:12], e["n"], "tokens")

    def _replace_chain(self, parent):
        """Budget pressure (the folder above 80 % of the budget) and a chain that holds twice its full save's bytes: the
        next save of this conversation is full, and the old chain goes (it holds only prefixes of the new save)."""
        chain = self._chain(parent) or []
        if len(chain) < 2:
            return None
        total = sum(e["bytes"] for e in self.index.values())
        cbytes = sum(self.index[x]["bytes"] for x in chain)
        if total > 0.8 * self.budget and cbytes >= 2 * self.index[chain[0]]["bytes"]:
            return chain
        return None

    def _evict(self):
        """Remove the least recently used saves until the folder fits the budget. A chain (a full save and its deltas)
        goes as a whole, so no delta is left without its parent."""
        total = sum(e["bytes"] for e in self.index.values())
        groups = {}
        for sha in self.index:
            groups.setdefault(self._root(sha), []).append(sha)
        order = sorted(groups.items(), key=lambda kv: max(self.index[x]["last"] for x in kv[1]))
        for root, members in order:
            if total <= self.budget:
                break
            for sha in sorted(members, key=lambda x: -self.index[x]["depth"]):   # deltas first, the full save last
                e = self.index[sha]
                ok = True
                for p in self._files(sha):
                    try:
                        if os.path.exists(p):
                            os.remove(p)
                    except OSError:
                        ok = False
                if not ok:   # keep the entry when a file could not be removed (review N8); its parents stay too
                    break
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

    def _get(self, path, auth, timeout=60):
        headers = {"Authorization": auth} if auth else {}
        with urllib.request.urlopen(urllib.request.Request(self.upstream + path, headers=headers), timeout=timeout) as r:
            return json.loads(r.read() or b"null")

    def _slot_tokens(self, auth):
        """Tokens in the slot now (GET /slots n_prompt_tokens; the server keeps it after the task ends, unlike its
        per-request counts, which it resets)."""
        return int(self._get("/slots", auth)[0].get("n_prompt_tokens") or 0)

    def _store(self, tmp, saved, parent=None):
        """Give a finished save in tmp (+ its .draft sidecar) its final name and index entry; returns (sha, bytes). saved
        is the whole token list (for a delta too); parent: the save a delta continues."""
        sha = _sha(saved)
        os.replace(os.path.join(self.folder, tmp), self._bin(sha))
        if os.path.exists(os.path.join(self.folder, tmp + ".draft")):   # the draft sidecar goes with it (review B1)
            os.replace(os.path.join(self.folder, tmp + ".draft"), self._bin(sha) + ".draft")
        elif os.path.exists(self._bin(sha) + ".draft"):   # review: a sidecar of an older save of the same tokens
            try:
                os.remove(self._bin(sha) + ".draft")
            except OSError:
                pass
        with open(self._files(sha)[2], "wb") as f:
            array.array("I", saved).tofile(f)
        size = sum(os.path.getsize(p) for p in self._files(sha) if os.path.exists(p))
        depth = self.index[parent]["depth"] + 1 if parent else 0
        self.index[sha] = {"n": len(saved), "last": time.time(), "bytes": size, "parent": parent, "depth": depth}
        key = self._conv_key(saved)
        if depth >= self.chain > 0:   # a long chain: a full save the next time the layer is idle
            self.compact = (key, getattr(self, "last_auth", ""))
        elif depth == 0 and self.compact and self.compact[0] == key:
            self.compact = None
        self._note({"sha": sha, **self.index[sha]})
        return sha, size

    def _toks_of(self, sha):
        a = array.array("I")
        a.frombytes(open(self._files(sha)[2], "rb").read())
        return list(a)

    def _delta_ok(self, auth):
        if self.delta_ok is None:
            try:
                self.delta_ok = bool((self._get("/props", auth) or {}).get("slot_save_delta"))
            except Exception:
                self.delta_ok = False
            self.log("delta saves", "on" if (self.delta_ok and self.chain > 0) else "off (server or BONSAI_SLOT_CACHE_CHAIN)")
        return self.delta_ok and self.chain > 0

    def _tmp(self):
        tmp = PREFIX + "saving-%d.bin" % os.getpid()
        for p in (tmp, tmp + ".draft"):   # a stale sidecar from a crashed save must not be renamed with this one
            try:
                os.remove(os.path.join(self.folder, p))
            except OSError:
                pass
        return tmp

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
        self.last_auth = auth
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
                chain = self._chain(best_sha)
                if not chain or (len(chain) > 1 and not self._delta_ok(auth)):   # review: never a delta on its own
                    raise ValueError("chain of %s not usable (broken, or the server cannot append)" % best_sha[:12])
                for i, link in enumerate(chain):   # the full save, then each delta after the slot's cells
                    self._post("/slots/0?action=restore", {"filename": self._name(link), **({"append": True} if i else {})}, auth)
                if len(chain) > 1:
                    info["slot_cache_chain"] = len(chain)
                self.index[best_sha]["last"] = time.time()
                self._note({"sha": best_sha, **self.index[best_sha]})
                common = best_n
                info["slot_cache_restored"] = best_n
                info["slot_cache_restore_s"] = round(time.time() - t1, 2)
                self.log("restored", best_sha[:12], best_n, "tokens in", info["slot_cache_restore_s"], "s")
            except Exception as e:
                self.log("restore failed:", repr(e))
                self.held = []   # a failed append may have emptied the slot
                common = 0
        key = self._conv_key(toks)
        # the prefix test of this conversation's last answer is valid only when nothing else used the slot since
        probe = self.probe if (not force_save and self.probe and self.probe[0] == key
                               and not info.get("slot_cache_restored")) else None
        if not force_save:
            self.probe = None
            self.wait = (key, probe[1]) if (probe and self.after_on) else None
        every = self.after_on and self.every and not force_save and self._delta_ok(auth)
        if every:
            la = self.last_after.get(key)
            if la in self.index:   # the exact test: was the state after its last answer a prefix of this prompt?
                ok = la == best_sha or (best_sha in self.index and la in (self._chain(best_sha) or []))
                if self.conv.get(key) is not ok:
                    self.log("after-answer test", key[:12], "pass" if ok else "fail", "(exact)")
                self._set_conv(key, ok)
            self.wait = None   # no cached-token test in this mode
        after_mode = self.after_on and not force_save and (self.conv.get(key) is True or (every and self.conv.get(key) is not False))
        if after_mode:
            info["slot_cache_after"] = "on"   # this conversation saves after the answer: no save before the request
        need = (1 if best_n == 0 else self.grow) if force_save else self.grow
        if not after_mode and len(base) < len(toks) and len(base) - max(best_n, 0) >= need:
            tmp = self._tmp()
            try:
                t1 = time.time()
                pr = self._post("/completion", {"prompt": base, "n_predict": 0, "cache_prompt": True}, auth)
                t2 = time.time()
                if self.wait:   # the prefill-only call is the request that read this turn's tokens
                    self.cached((pr.get("timings") or {}).get("cache_n"))
                # a delta of the best saved prefix when the slot starts with it (restored, or held in memory)
                parent = best_sha if (best_sha in self.index and not force_save
                                      and (info.get("slot_cache_restored") or best_n <= common)
                                      and self.index[best_sha]["depth"] < self.chain_max and self._delta_ok(auth)) else None
                body = {"filename": tmp, **({"pos_min": self.index[parent]["n"]} if parent else {})}
                r = self._post("/slots/0?action=save", body, auth)
                if parent:   # exact: the parent's tokens + the file's tokens, a prefix of the prompt
                    saved = self._toks_of(parent) + read_tokens(os.path.join(self.folder, tmp))
                    if len(saved) > len(base) or saved != base[:len(saved)]:
                        raise ValueError("the delta does not continue the saved prefix (%d tokens)" % len(saved))
                    info["slot_cache_delta_of"] = self.index[parent]["n"]
                else:
                    n = int(r.get("n_saved") or len(base))
                    saved = base[:n] if n <= len(base) else base   # the server may hold back the last token
                sha, size = self._store(tmp, saved, parent)
                best_sha = sha
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
            if info.get("slot_cache_saved") or info.get("slot_cache_restored"):
                self.probe = None   # the slot no longer holds the state after the last answer (review: a false pass)
            if info.get("slot_cache_saved"):
                self.held = base
            elif info.get("slot_cache_restored"):
                self.held = toks[:info["slot_cache_restored"]]   # a restore-only read-ahead (re-review: blocking)
        else:
            self.held = toks
            self.last = {"key": key, "toks": toks, "every": every, "best": max(best_n, int(info.get("slot_cache_saved") or 0)),
                         "best_sha": best_sha if (info.get("slot_cache_restored") or info.get("slot_cache_saved")
                                                  or (best_sha and best_n <= common)) else None}
        info["slot_cache_s"] = round(time.time() - t0, 2)
        return info

    def cached(self, n):
        """The prefix test: the layer passes the cached-token count (timings.cache_n) of the first reply after before().
        Passes when that request reused all the tokens the slot held after the conversation's last answer."""
        w, self.wait = self.wait, None
        try:
            n = int(n)
        except (TypeError, ValueError):
            return None
        if not w:
            return None
        ok = n >= w[1]
        self._set_conv(w[0], ok)
        self.log("after-answer test", w[0][:12], "pass" if ok else "fail", "(cached", n, "of", w[1], ")")
        return ok

    def after(self, auth):
        """Call with the lock held, after the answer went to the client. Resolves the prefix test of the last answer,
        starts the test of this one, and in a conversation that passed the test saves the slot when it grew by
        BONSAI_SLOT_CACHE_GROW or more since the best saved prefix. Returns an info dict (also for the log)."""
        last, self.last = self.last, None
        if not self.after_on or not last:
            return {}
        t0 = time.time()
        info = {}
        self.wait = None   # a reply without timings: no result for this test
        n = self._slot_tokens(auth)
        toks = last["toks"]
        every = last.get("every")
        self.probe = (last["key"], n) if (n > len(toks) and not every) else None
        want = (n > len(toks) and self.conv.get(last["key"]) is not False) if every else \
            (self.conv.get(last["key"]) is True and n - last["best"] >= self.grow)
        if want:
            tmp = self._tmp()
            parent = last.get("best_sha")
            if not (parent in self.index and self.index[parent]["depth"] < self.chain_max and self._delta_ok(auth)):
                parent = None
            old_chain = self._replace_chain(parent) if parent else None
            if old_chain:
                parent = None   # a full save; the old chain goes after it is stored
            try:
                t1 = time.time()
                body = {"filename": tmp}
                if parent:
                    body["pos_min"] = self.index[parent]["n"]
                r = self._post("/slots/0?action=save", body, auth)
                saved = read_tokens(os.path.join(self.folder, tmp))
                if parent:   # the file holds the tokens from pos_min on
                    saved = self._toks_of(parent) + saved
                if len(saved) <= len(toks) or saved[:len(toks)] != toks:   # another request used the slot in between
                    raise ValueError("the slot does not extend the request's tokens (%d tokens)" % len(saved))
                sha, size = self._store(tmp, saved, parent)
                if parent:
                    info["delta_of"] = self.index[parent]["n"]
                if old_chain:
                    self._drop([x for x in old_chain if x != sha], "replaced (budget)")
                    info["replaced_chain"] = len(old_chain)
                self.last_after[last["key"]] = sha
                self.held = saved
                info.update(saved=len(saved), save_s=round(time.time() - t1, 2))
                self.log("saved after the answer", sha[:12], len(saved), "tokens:", info["save_s"], "s, n_saved", r.get("n_saved"))
                self._evict()
            except Exception as e:
                self.log("save after the answer failed:", repr(e))
                info["failed"] = repr(e)[:200]
                for p in (tmp, tmp + ".draft"):
                    try:
                        os.remove(os.path.join(self.folder, p))
                    except OSError:
                        pass
        info["s"] = round(time.time() - t0, 2)
        return info
