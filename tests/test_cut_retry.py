"""Offline test: a reply that max_tokens cuts inside the layer's own run_python call is asked again without the tool.

Before the fix the layer dropped the half-written call and the client got content "" (found in a check on a sister serve). A fake
server answers with a cut run_python call when the request offers tools, and with plain text when it does not.
python tests/test_cut_retry.py
"""
import http.server
import json
import os
import sys
import threading
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "layer"))
import bonsai_layer  # noqa: E402

TEXT = "Warehouses keep spare parts to cut downtime."
S = {"calls": []}


class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        tools = [t["function"]["name"] for t in body.get("tools") or []]
        S["calls"].append({"tools": tools, "stream": bool(body.get("stream"))})
        cut_call = "run_python" in tools and S.get("cut", True)
        if not body.get("stream"):
            msg = {"role": "assistant", "content": ""}
            if cut_call:
                msg["tool_calls"] = [{"id": "x1", "type": "function",
                                      "function": {"name": "run_python", "arguments": '{"code":"text = \\"Ware'}}]
            else:
                msg["content"] = TEXT
            out = json.dumps({"object": "chat.completion", "choices": [{"index": 0, "message": msg,
                              "finish_reason": "length" if cut_call else "stop"}],
                              "usage": {"prompt_tokens": 10, "completion_tokens": 40, "total_tokens": 50}}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        tpl = {"id": "c1", "object": "chat.completion.chunk", "model": "m"}

        def ev(d):
            self.wfile.write(b"data: " + json.dumps(d).encode() + b"\n\n")
        if cut_call:
            ev(dict(tpl, choices=[{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": "x1", "type": "function",
                "function": {"name": "run_python", "arguments": '{"code":"text = \\"Ware'}}]}, "finish_reason": None}]))
            ev(dict(tpl, choices=[{"index": 0, "delta": {}, "finish_reason": "length"}]))
        else:
            ev(dict(tpl, choices=[{"index": 0, "delta": {"content": TEXT}, "finish_reason": None}]))
            ev(dict(tpl, choices=[{"index": 0, "delta": {}, "finish_reason": "stop"}]))
        ev(dict(tpl, choices=[], usage={"prompt_tokens": 10, "completion_tokens": 40, "total_tokens": 50}))
        self.wfile.write(b"data: [DONE]\n\n")


up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
bonsai_layer.Proxy.upstream = f"http://127.0.0.1:{up.server_address[1]}"
bonsai_layer.Proxy.api_key = None
bonsai_layer.Proxy.slots = None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), bonsai_layer.Proxy)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_address[1]}"
REQ = {"messages": [{"role": "user", "content": "Write a short report on spare parts."}], "max_tokens": 40,
       "api_cards": False, "api_lint": False, "finish_note": False, "chat_template_kwargs": {"enable_thinking": False}}


def post(body):
    return urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                                         headers={"Content-Type": "application/json"}), timeout=30).read()


def test_nonstream():
    S["calls"].clear()
    r = json.loads(post(REQ))
    m = r["choices"][0]["message"]
    assert m["content"] == TEXT and not m.get("tool_calls"), r
    assert [c["tools"] for c in S["calls"]] == [["run_python"], []], S["calls"]   # one retry, without our tool
    assert r["layer"].get("cut_retry") is True, r["layer"]
    print("non-stream: cut inside run_python -> one retry without the tool -> the text: ok")


def test_stream():
    S["calls"].clear()
    raw = post(dict(REQ, stream=True)).decode()
    text = "".join((json.loads(l[6:])["choices"][0]["delta"].get("content") or "")
                   for l in raw.splitlines() if l.startswith("data: {") and json.loads(l[6:]).get("choices"))
    assert text == TEXT, raw
    assert "run_python" not in raw, raw            # the half-written call never reaches the client
    assert [c["tools"] for c in S["calls"]] == [["run_python"], []], S["calls"]
    assert raw.rstrip().endswith("data: [DONE]"), raw
    evs = [json.loads(l[6:]) for l in raw.splitlines() if l.startswith("data: {")]
    fins = [i for i, e in enumerate(evs) for c in e.get("choices") or [] if c.get("finish_reason")]
    texts = [i for i, e in enumerate(evs) for c in e.get("choices") or [] if (c.get("delta") or {}).get("content")]
    assert len(fins) == 1 and fins[0] > max(texts), raw   # one finish chunk, after the text (review)
    print("stream: the same, one finish chunk after the text: ok")


def test_text_round_unchanged():
    S["calls"].clear()
    S["cut"] = False   # a normal answer: no retry, one call
    r = json.loads(post(REQ))
    assert r["choices"][0]["message"]["content"] == TEXT and len(S["calls"]) == 1, (r, S["calls"])
    S["cut"] = True
    print("a normal answer: one call, unchanged: ok")


if __name__ == "__main__":
    test_nonstream()
    test_stream()
    test_text_round_unchanged()
    print("ALL OK")
