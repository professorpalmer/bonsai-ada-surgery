"""Offline tests for the save after the answer in layer/slot_cache.py (BONSAI_SLOT_CACHE_AFTER, #138).
No GPU, no server: a fake upstream keeps one slot as a token list. A chat request reads its prompt (the cached count is
the common prefix with the slot) and appends its answer tokens; /completion reads a prefill-only prompt; GET /slots gives
the slot's token count and the last cached count; a save writes the real slot-file header (magic, version 2, count,
tokens) and a restore reads it back.

python tests/test_slot_after.py
"""
import array
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

GEN = "@@"
S = {"slot": [], "cached": 0, "calls": [], "folder": tempfile.mkdtemp()}


def render(msgs, gen=True):
    # a past answer renders after the same generation prompt it was generated under (the Bonsai template with thinking off)
    return "".join((GEN if m["role"] == "assistant" else "") + m["content"] for m in msgs) + (GEN if gen else "")


def toks(text):
    return [ord(c) for c in text]


def answer_for(prompt):
    return "A%d." % (len(prompt) % 97)


def common(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


class Fake(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, out):
        d = json.dumps(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(d)))
        self.end_headers()
        self.wfile.write(d)

    def do_GET(self):
        S["calls"].append("GET " + self.path)
        if self.path == "/slots":
            return self._send([{"id": 0, "n_prompt_tokens": len(S["slot"]), "n_prompt_tokens_cache": S["cached"]}])
        self._send({})

    def do_POST(self):
        b = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
        S["calls"].append(self.path)
        if self.path == "/apply-template":
            return self._send({"prompt": render(b["messages"], b.get("add_generation_prompt") is not False)})
        if self.path == "/tokenize":
            return self._send({"tokens": toks(b["content"])})
        if self.path == "/completion":
            assert b["n_predict"] == 0
            S["cached"] = common(S["slot"], b["prompt"])
            S["slot"] = list(b["prompt"])
            return self._send({})
        if self.path == "/v1/chat/completions":
            p = toks(render(b["messages"]))
            S["cached"] = common(S["slot"], p)
            a = answer_for(p)
            S["slot"] = p + toks(a)   # the slot holds the prompt and the answer tokens (the end token is not read)
            return self._send({"choices": [{"index": 0, "finish_reason": "stop",
                                            "message": {"role": "assistant", "content": a}}]})
        if self.path.startswith("/slots/0?action=save"):
            with open(os.path.join(S["folder"], b["filename"]), "wb") as f:
                array.array("I", [slot_cache.GGSQ, 2, len(S["slot"])] + S["slot"]).tofile(f)
                f.write(b"state" * 20)
            open(os.path.join(S["folder"], b["filename"] + ".draft"), "wb").write(b"d" * 10)
            return self._send({"n_saved": len(S["slot"])})
        if self.path.startswith("/slots/0?action=restore"):
            S["slot"] = slot_cache.read_tokens(os.path.join(S["folder"], b["filename"]))
            return self._send({"n_restored": len(S["slot"])})
        self._send({})


up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
UP = f"http://127.0.0.1:{up.server_address[1]}"
LOG = []


def cache(after=True):
    return slot_cache.SlotCache(UP, S["folder"], min_tokens=50, grow=20, budget_gb=1, min_gain=5, after=after,
                                log=lambda *a: LOG.append(" ".join(str(x) for x in a)))


def chat(c, msgs):
    """One turn through the cache hooks as the layer runs it: before, the request, after."""
    body = {"messages": msgs}
    with c.lock:
        info = c.before(body, "")
        r = json.loads(urllib.request.urlopen(urllib.request.Request(
            UP + "/v1/chat/completions", data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"})).read())
        info["after"] = c.after("")
    return r["choices"][0]["message"]["content"], info


def reset():
    S["slot"], S["cached"], S["calls"] = [], 0, []
    S["folder"] = tempfile.mkdtemp()
    LOG.clear()


DOC = {"role": "user", "content": "D" * 120 + "Q1?"}


def turn_msgs(answers, n, rewrite=False):
    msgs = [DOC]
    for k in range(1, n):
        a = answers[k - 1]
        msgs.append({"role": "assistant", "content": ("x" + a) if rewrite else a})
        msgs.append({"role": "user", "content": "T%d" % k + "t" * 25 + "?"})
    return msgs


def test_pass_then_after_mode():
    reset()
    c = cache()
    answers = []
    a, info = chat(c, turn_msgs(answers, 1))
    answers.append(a)
    assert info["status"] == "saved", info                     # turn 1: test unknown, the save before the request runs
    assert c.probe and c.probe[1] == len(S["slot"]), c.probe
    a, info = chat(c, turn_msgs(answers, 2))
    answers.append(a)
    key = c._conv_key(toks(render(turn_msgs(answers, 2))))
    assert c.conv.get(key) is True, (c.conv, LOG)              # the answer of turn 1 was a prefix of turn 2
    S["calls"].clear()
    a, info = chat(c, turn_msgs(answers, 3))
    answers.append(a)
    assert info.get("slot_cache_after") == "on", info
    assert "/completion" not in S["calls"], S["calls"]         # no prefill-only call in after mode
    assert info["after"].get("saved") == len(S["slot"]), info  # grew >= 20 since the turn-2 save: saved after the answer
    saved = list(S["slot"])
    sha = slot_cache._sha(saved)
    assert sha in c.index and c.held == saved
    assert slot_cache.read_tokens(c._bin(sha)) == saved
    # restart: a new layer (the result is on disk) and an empty server slot
    S["slot"], S["cached"] = [], 0
    c2 = cache()
    assert c2.conv.get(key) is True
    S["calls"].clear()
    a, info = chat(c2, turn_msgs(answers, 4))
    assert info.get("slot_cache_restored") == len(saved), info  # restored the state after the turn-3 answer
    assert "/completion" not in S["calls"], S["calls"]
    assert S["cached"] == len(saved)                            # the request read only the new turn
    print("pass -> after mode, save after the answer, restore after a restart: ok")


def test_rewritten_answer_fails():
    reset()
    c = cache()
    answers = []
    for n in (1, 2):
        a, info = chat(c, turn_msgs(answers, n, rewrite=True))
        answers.append(a)
    key = c._conv_key(toks(render(turn_msgs(answers, 2, rewrite=True))))
    assert c.conv.get(key) is False, (c.conv, LOG)
    S["calls"].clear()
    a, info = chat(c, turn_msgs(answers + ["z"], 3, rewrite=True))
    assert "slot_cache_after" not in info and "/completion" in S["calls"], (info, S["calls"])   # back to the save before
    print("client rewrites the answer: test fails, save before the request again: ok")


def test_other_conversation_between():
    reset()
    c = cache()
    answers = []
    a, _ = chat(c, turn_msgs(answers, 1))
    answers.append(a)
    chat(c, [{"role": "user", "content": "E" * 120 + "other?"}])   # another long conversation uses the slot
    chat(c, turn_msgs(answers, 2))
    key = c._conv_key(toks(render(turn_msgs(answers, 2))))
    assert key not in c.conv, (c.conv, LOG)                        # no result from a test that another request broke
    print("another conversation between two turns: test not counted: ok")


def test_slot_changed_before_save():
    reset()
    c = cache()
    answers = []
    for n in (1, 2):
        a, _ = chat(c, turn_msgs(answers, n))
        answers.append(a)
    body = {"messages": turn_msgs(answers, 3)}
    with c.lock:
        c.before(body, "")
        urllib.request.urlopen(urllib.request.Request(UP + "/v1/chat/completions", data=json.dumps(body).encode(),
                                                      headers={"Content-Type": "application/json"})).read()
        S["slot"] = toks("F" * 200)   # the slot now holds other tokens (e.g. a request that did not pass the layer)
        n_index = len(c.index)
        got = c.after("")
    assert "failed" in got and len(c.index) == n_index, got
    assert not [f for f in os.listdir(S["folder"]) if f.startswith("lc-saving-")]
    print("slot changed before the save: no file, no index entry: ok")


def test_off_by_default():
    reset()
    old = os.environ.pop("BONSAI_SLOT_CACHE_AFTER", None)
    os.environ["BONSAI_SLOT_SAVE_PATH"] = S["folder"]
    try:
        c = slot_cache.SlotCache.from_env(UP)
        assert c.after_on is False
        os.environ["BONSAI_SLOT_CACHE_AFTER"] = "1"
        assert slot_cache.SlotCache.from_env(UP).after_on is True
    finally:
        os.environ.pop("BONSAI_SLOT_SAVE_PATH", None)
        os.environ.pop("BONSAI_SLOT_CACHE_AFTER", None)
        if old is not None:
            os.environ["BONSAI_SLOT_CACHE_AFTER"] = old
    S["calls"].clear()
    c = cache(after=False)
    chat(c, turn_msgs([], 1))
    assert "GET /slots" not in S["calls"], S["calls"]   # off: no extra server call at all
    print("off by default, no GET /slots when off: ok")


def test_layer_hook():
    reset()
    bonsai_layer.Proxy.upstream = UP
    bonsai_layer.Proxy.slots = cache()
    bonsai_layer.Proxy.api_key = None
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), bonsai_layer.Proxy)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"
    body = {"messages": turn_msgs([], 1), "code_interpreter": False, "api_cards": False, "api_lint": False,
            "finish_note": False}
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        base + "/v1/chat/completions", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})).read())
    assert r["choices"][0]["message"]["content"]
    for _ in range(50):   # busy until after() is done: the answer reaches the client first
        st = json.loads(urllib.request.urlopen(base + "/layer/slot-cache").read())
        if not st["busy"]:
            break
        time.sleep(0.1)
    assert st == {"on": True, "after": True, "busy": False}, st
    i = S["calls"].index("/v1/chat/completions")
    assert "GET /slots" in S["calls"][i:], S["calls"]   # after() ran once the answer was out
    assert bonsai_layer.Proxy.slots.probe, LOG
    srv.shutdown()
    bonsai_layer.Proxy.slots = None
    print("layer hook: after() runs after the answer, status endpoint: ok")


if __name__ == "__main__":
    test_pass_then_after_mode()
    test_rewritten_answer_fails()
    test_other_conversation_between()
    test_slot_changed_before_save()
    test_off_by_default()
    test_layer_hook()
    print("ALL OK")
