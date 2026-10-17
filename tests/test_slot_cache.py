"""Offline tests for layer/slot_cache.py and the layer's streamed path with the cache on (#138 T1-c). No GPU, no server:
a fake upstream implements /apply-template, /tokenize, /completion, /slots/0?action=save|restore and a streamed
/v1/chat/completions. The layer's code sandbox is stubbed (the tests set no code_interpreter work).

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
CALLS, LAST = [], [0]
FOLDER = tempfile.mkdtemp()


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
            out = {"prompt": "".join(m["content"] for m in b["messages"]) + ("" if b.get("add_generation_prompt") is False else GEN)}
        elif self.path == "/tokenize":
            out = {"tokens": [ord(c) for c in b["content"]]}
        elif self.path == "/completion":
            assert b["n_predict"] == 0
            assert b["prompt"][-2:] != [ord(c) for c in GEN], "the prefill must stop before the generation prompt"
            time.sleep(DELAY[0])
            LAST[0] = len(b["prompt"])
            out = {}
        elif self.path.startswith("/slots/0?action=save"):
            open(os.path.join(FOLDER, b["filename"]), "wb").write(b"x" * 1000)
            out = {"n_saved": LAST[0]}
        else:
            out = {}
        d = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)


DELAY = [0.0]
up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
UP = f"http://127.0.0.1:{up.server_address[1]}"


def cache():
    return slot_cache.SlotCache(UP, FOLDER, min_tokens=100, grow=50, budget_gb=1e-5, log=lambda *a: None, min_gain=10)


def req(*texts):
    return {"messages": [{"role": "user" if i % 2 == 0 else "assistant", "content": t} for i, t in enumerate(texts)]}


def test_cache_logic():
    A = "a" * 300
    c = cache()
    CALLS.clear()
    info = c.before(req(A), "Bearer k")
    assert info["slot_cache_saved"] == 300 and info["slot_cache_gen_prompt_tokens"] == 2, info
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
    CALLS.clear()
    info = c2.before(req("z" * 400), "Bearer k")                                              # other conversation
    assert "slot_cache_restored" not in info and info["slot_cache_saved"] == 400
    assert not [f for f in os.listdir(FOLDER) if f.startswith("saving")], "temp save files left"
    print("cache logic: ok")


def test_stream_keepalive():
    P = bonsai_layer.Proxy
    P.upstream, P.keepalive = UP, 0.3
    P.slots = slot_cache.SlotCache(UP, tempfile.mkdtemp(), min_tokens=100, grow=50, log=lambda *a: None, min_gain=10)
    lay = http.server.ThreadingHTTPServer(("127.0.0.1", 0), P)
    threading.Thread(target=lay.serve_forever, daemon=True).start()
    DELAY[0] = 1.5                                                                            # a slow prefill-only call
    body = {"messages": [{"role": "user", "content": "a" * 300}], "stream": True,
            "tools": [{"type": "function", "function": {"name": "x", "parameters": {}}}]}
    rq = urllib.request.Request(f"http://127.0.0.1:{lay.server_address[1]}/v1/chat/completions",
                                data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.time()
    r = urllib.request.urlopen(rq, timeout=1.0)                                               # 1 s read timeout
    first, data = None, b""
    while True:
        chunk = r.read1(4096)
        if not chunk:
            break
        first = first if first is not None else time.time() - t0
        data += chunk
    DELAY[0] = 0.0
    assert first < 1.0 and data.count(b'"content"') == 2 and b"[DONE]" in data and b": keep-alive" in data
    print(f"stream keep-alive: ok (first bytes after {first:.2f} s)")


if __name__ == "__main__":
    test_cache_logic()
    test_stream_keepalive()
    print("ALL OK")
