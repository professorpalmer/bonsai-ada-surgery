"""Offline tests for layer/slot_cache.py and the layer's streamed path with the cache on (#138 T1-c, PR #157 review items).
No GPU, no server: a fake upstream implements /apply-template, /tokenize, /completion, /slots/0?action=save|restore (with the
.draft sidecar) and a streamed /v1/chat/completions. The layer's code sandbox is stubbed (the tests run no code).

python tests/test_slot_cache.py
"""
import http.server
import json
import os
import sys
import tempfile
import threading
import time
import types
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for name in ("wasmtime", "sandbox"):
    sys.modules.setdefault(name, types.ModuleType(name))
sys.path.insert(0, os.path.join(ROOT, "layer"))
import bonsai_layer  # noqa: E402
import slot_cache  # noqa: E402

GEN = "@@"          # stands for the generation prompt (<|im_start|>assistant ...)
CALLS, LAST, DELAY = [], [0], [0.0]
FOLDER = [tempfile.mkdtemp()]


class Fake(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_POST(self):
        b = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
        CALLS.append(self.path)
        if self.path == "/v1/chat/completions":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close")
            self.end_headers()
            for w in ("hel", "lo"):
                self.wfile.write(b"data: " + json.dumps({"choices": [{"delta": {"content": w}}]}).encode() + b"\n\n")
                self.wfile.flush()
            self.wfile.write(b"data: [DONE]\n\n")
            return
        if self.path == "/apply-template":
            # the effort word sits at the start of the prompt, as in the real template (review B2)
            pre = "E:" + b["reasoning_effort"] + ";" if "reasoning_effort" in b else ""
            out = {"prompt": pre + "".join(m["content"] if isinstance(m["content"], str) else "[media]" for m in b["messages"])
                   + ("" if b.get("add_generation_prompt") is False else GEN)}
        elif self.path == "/tokenize":
            out = {"tokens": [ord(c) for c in b["content"]]}
        elif self.path == "/completion":
            assert b["n_predict"] == 0
            assert b["prompt"][-2:] != [ord(c) for c in GEN], "the prefill must stop before the generation prompt"
            time.sleep(DELAY[0])
            LAST[0] = len(b["prompt"])
            out = {}
        elif self.path.startswith("/slots/0?action=save"):
            for suffix in ("", ".draft"):   # the server writes the sidecar next to the slot file (patches 0062 / 0063)
                open(os.path.join(FOLDER[0], b["filename"] + suffix), "wb").write(b"x" * 1000)
            out = {"n_saved": LAST[0]}
        else:
            out = {}
        d = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)


up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
UP = f"http://127.0.0.1:{up.server_address[1]}"


def cache(**kw):
    args = dict(min_tokens=100, grow=50, budget_gb=1e-3, log=lambda *a: None, min_gain=10)
    args.update(kw)
    return slot_cache.SlotCache(UP, FOLDER[0], **args)


def req(*texts, **extra):
    return {"messages": [{"role": "user" if i % 2 == 0 else "assistant", "content": t} for i, t in enumerate(texts)], **extra}


def test_cache_logic():
    FOLDER[0] = tempfile.mkdtemp()
    A = "a" * 300
    c = cache()
    CALLS.clear()
    info = c.before(req(A), "Bearer k")
    assert info["slot_cache_saved"] == 300 and info["slot_cache_gen_prompt_tokens"] == 2, info
    name = next(f for f in os.listdir(FOLDER[0]) if f.endswith(".bin"))
    assert name.startswith("lc-"), "R2: cache files carry the lc- prefix"
    assert os.path.exists(os.path.join(FOLDER[0], name + ".draft")), "B1: the .draft sidecar must be renamed with the .bin"
    assert not [f for f in os.listdir(FOLDER[0]) if "saving" in f], "temp save files left"
    CALLS.clear()
    assert "slot_cache_saved" not in c.before(req(A, "ANSWER", "b" * 20), "Bearer k")          # small growth: no save
    assert not any("slots" in p for p in CALLS)
    CALLS.clear()
    c2 = cache()                                                                              # a restart
    info = c2.before(req(A, "ANSWER", "b" * 60), "Bearer k")
    assert info.get("slot_cache_restored") == 300, info
    CALLS.clear()
    c2.before(req("hi"), "Bearer k")                                                          # short: nothing
    assert not any("slots" in p or p == "/completion" for p in CALLS), CALLS
    info = c2.before(req("z" * 400), "Bearer k")                                              # other conversation
    assert "slot_cache_restored" not in info and info["slot_cache_saved"] == 400
    print("cache logic + B1 sidecar rename: ok")


def test_b2_effort_in_template():
    FOLDER[0] = tempfile.mkdtemp()
    c = cache()
    c.before(req("a" * 300, reasoning_effort="low"), "Bearer k")
    c2 = cache()
    info = c2.before(req("a" * 300, "ANS", "b" * 60, reasoning_effort="low"), "Bearer k")
    assert info.get("slot_cache_restored"), "B2: reasoning_effort must reach /apply-template, so the saved prefix matches"
    info = cache().before(req("a" * 300, "ANS", "b" * 60, reasoning_effort="high"), "Bearer k")
    assert "slot_cache_restored" not in info, "another effort renders other tokens: no restore"
    print("B2 reasoning_effort: ok")


def test_b3_media_skipped():
    FOLDER[0] = tempfile.mkdtemp()
    CALLS.clear()
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": "a" * 300},
                                                      {"type": "image_url", "image_url": {"url": "data:,"}}]}]}
    info = cache().before(body, "Bearer k")
    assert info == {"slot_cache": "skipped (media)"} and CALLS == [], (info, CALLS)
    print("B3 media skipped: ok")


def test_n1_bad_env():
    os.environ.update({"BONSAI_SLOT_SAVE_PATH": FOLDER[0], "BONSAI_SLOT_CACHE_MIN": "lots"})
    try:
        assert slot_cache.SlotCache.from_env(UP, log=lambda *a: None) is None, "N1: a bad value turns the cache off"
    finally:
        for k in ("BONSAI_SLOT_SAVE_PATH", "BONSAI_SLOT_CACHE_MIN"):
            os.environ.pop(k, None)
    print("N1 bad env -> cache off: ok")


def test_n8_cleanup_and_index():
    FOLDER[0] = tempfile.mkdtemp()
    c = cache()
    c.before(req("a" * 300), "Bearer k")
    open(os.path.join(FOLDER[0], "lc-saving-999.bin"), "wb").write(b"x")
    open(os.path.join(FOLDER[0], "lc-saving-999.bin.draft"), "wb").write(b"x")
    orphan = "lc-" + "f" * 64
    open(os.path.join(FOLDER[0], orphan + ".bin"), "wb").write(b"x")
    open(os.path.join(FOLDER[0], "keep-me.bin"), "wb").write(b"x")      # not a cache name: left alone
    users = "e" * 64 + ".bin"                                          # a user's own save named by sha256: left alone (R2)
    open(os.path.join(FOLDER[0], users), "wb").write(b"x")
    open(os.path.join(FOLDER[0], "saving-1.bin"), "wb").write(b"x")    # a user's file without the prefix: left alone
    with open(os.path.join(FOLDER[0], "lc-index.jsonl"), "a") as f:
        f.write("not json\n")
    c2 = cache()
    left = os.listdir(FOLDER[0])
    assert len(c2.index) == 1, "N8: the bad index line must not lose the good entries"
    assert not [f for f in left if f.startswith("lc-saving-")] and orphan + ".bin" not in left, left
    assert "keep-me.bin" in left and users in left and "saving-1.bin" in left, left
    print("N8 cleanup + index: ok")


def test_n9_equal_length():
    FOLDER[0] = tempfile.mkdtemp()
    c = cache()
    full = [ord(ch) for ch in "a" * 300 + GEN]                     # the whole next request, generation prompt included
    sha = slot_cache._sha(full)
    open(os.path.join(FOLDER[0], "lc-" + sha + ".bin"), "wb").write(b"x")
    c.index[sha] = {"n": len(full), "last": time.time(), "bytes": 1}
    info = c.before(req("a" * 300), "Bearer k")
    assert "slot_cache_restored" not in info, "N9: a state as long as the request itself must not be restored"
    print("N9 equal length: ok")


def start_layer(api_key=None):
    P = bonsai_layer.Proxy
    P.upstream, P.keepalive, P.api_key = UP, 0.3, api_key
    FOLDER[0] = tempfile.mkdtemp()   # the fake server writes its slot files here: the cache must use the same folder
    P.slots = slot_cache.SlotCache(UP, FOLDER[0], min_tokens=100, grow=50, log=lambda *a: None, min_gain=10)
    lay = http.server.ThreadingHTTPServer(("127.0.0.1", 0), P)
    threading.Thread(target=lay.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{lay.server_address[1]}", P


def stream(url, auth=None, timeout=1.0):
    body = {"messages": [{"role": "user", "content": "a" * 300}], "stream": True,
            "tools": [{"type": "function", "function": {"name": "x", "parameters": {}}}]}
    h = {"Content-Type": "application/json", **({"Authorization": auth} if auth else {})}
    t0 = time.time()
    r = urllib.request.urlopen(urllib.request.Request(url + "/v1/chat/completions", data=json.dumps(body).encode(), headers=h), timeout=timeout)
    first, data = None, b""
    while True:
        chunk = r.read1(4096)
        if not chunk:
            break
        first = first if first is not None else time.time() - t0
        data += chunk
    return first, data


def test_stream_keepalive_and_n3():
    url, P = start_layer()
    DELAY[0] = 1.5                                                    # a slow prefill-only call
    first, data = stream(url)
    assert first < 1.0 and data.count(b'"content"') == 2 and b"[DONE]" in data and b": keep-alive" in data
    # N3: a second streamed request while the first holds the lock gets its headers + keep-alive at once
    res = {}
    FOLDER[0] = tempfile.mkdtemp()
    P.slots = slot_cache.SlotCache(UP, FOLDER[0], min_tokens=100, grow=50, log=lambda *a: None, min_gain=10)
    th = threading.Thread(target=lambda: res.setdefault("a", stream(url, timeout=5.0)))
    th.start()
    time.sleep(0.2)
    first_b, data_b = stream(url, timeout=1.0)                        # 1 s read timeout while A holds the slot ~1.5 s
    th.join()
    DELAY[0] = 0.0
    assert first_b < 1.0 and b"[DONE]" in data_b, first_b
    print(f"stream keep-alive: ok (first bytes after {first:.2f} s); N3 second stream first bytes after {first_b:.2f} s")


def test_r1_keepalive_zero():
    url, P = start_layer()
    P.keepalive = 0
    CALLS.clear()
    stream(url, timeout=5.0)
    P.keepalive = 0.3
    assert "/apply-template" in CALLS and "/completion" in CALLS, "R1: with --keepalive 0 the check still runs"
    assert CALLS.index("/completion") < CALLS.index("/v1/chat/completions"), CALLS
    print("R1 keepalive 0: ok")


def test_t1d_read_ahead():
    url, P = start_layer()
    CALLS.clear()
    body = {"messages": [{"role": "user", "content": "r" * 400}], "stream": True, "prefill_only": True,
            "tools": [{"type": "function", "function": {"name": "x", "parameters": {}}}]}
    rq = urllib.request.Request(url + "/v1/chat/completions", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    out = json.loads(urllib.request.urlopen(rq, timeout=5).read())
    assert out["prefill_only"] and out["slot_cache"].get("slot_cache_saved") == 400, out
    assert "/v1/chat/completions" not in CALLS, "a read-ahead must not generate"
    CALLS.clear()
    P.slots = slot_cache.SlotCache(UP, P.slots.folder, min_tokens=100, grow=50, log=lambda *a: None, min_gain=10)   # restart
    body2 = {"messages": [{"role": "user", "content": "r" * 400}, {"role": "assistant", "content": "A"},
                          {"role": "user", "content": "q" * 30}], "stream": True,
             "tools": [{"type": "function", "function": {"name": "x", "parameters": {}}}]}
    rq = urllib.request.Request(url + "/v1/chat/completions", data=json.dumps(body2).encode(), headers={"Content-Type": "application/json"})
    data = urllib.request.urlopen(rq, timeout=5).read()
    assert b"[DONE]" in data and "/slots/0?action=restore" in CALLS, CALLS
    print("T1-d read ahead: ok")


def test_n6_unauthenticated():
    url, P = start_layer(api_key="secret")
    CALLS.clear()
    try:
        stream(url, auth="Bearer wrong", timeout=2.0)
    except Exception:
        pass
    assert "/apply-template" not in CALLS and P.slots.held == [], "N6: a request with a wrong key must not touch the cache"
    print("N6 unauthenticated request: ok")


if __name__ == "__main__":
    test_cache_logic()
    test_b2_effort_in_template()
    test_b3_media_skipped()
    test_n1_bad_env()
    test_n8_cleanup_and_index()
    test_n9_equal_length()
    test_stream_keepalive_and_n3()
    test_r1_keepalive_zero()
    test_t1d_read_ahead()
    test_n6_unauthenticated()
    print("ALL OK")
