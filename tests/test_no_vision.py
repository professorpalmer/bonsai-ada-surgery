"""Offline test: without a vision projector the layer replaces images with a text note (issue #7).

A fake server answers /props with modalities.vision (switchable) and, like llama-server without mmproj, answers
HTTP 500 to any request that carries an "image_url" part.
python tests/test_no_vision.py
"""
import http.server
import json
import os
import sys
import threading
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "layer"))
import bonsai_layer  # noqa: E402

S = {"vision": False, "bodies": []}
IMG = {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="}}


class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        out = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_GET(self):
        if self.path == "/props":
            return self._send(200, {"modalities": {"vision": S["vision"], "audio": False}})
        self._send(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        S["bodies"].append(body)
        if '"image_url"' in json.dumps(body) and not S["vision"]:
            return self._send(500, {"error": {"code": 500, "message": "image input is not supported - hint: if this "
                                              "is unexpected, you may need to provide the mmproj"}})
        if self.path.endswith("/responses"):
            return self._send(200, {"object": "response", "output_text": "ok"})
        self._send(200, {"object": "chat.completion", "choices": [{"index": 0, "finish_reason": "stop",
                         "message": {"role": "assistant", "content": "I see a note instead of the image."}}],
                         "usage": {"prompt_tokens": 10, "completion_tokens": 8, "total_tokens": 18}})


up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
bonsai_layer.Proxy.upstream = f"http://127.0.0.1:{up.server_address[1]}"
bonsai_layer.Proxy.api_key = None
bonsai_layer.Proxy.slots = None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), bonsai_layer.Proxy)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_address[1]}"
PLAIN = {"api_cards": False, "api_lint": False, "finish_note": False, "code_interpreter": False,
         "chat_template_kwargs": {"enable_thinking": False}}


def post(path, body):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def reset(vision):
    S["vision"] = vision
    S["bodies"].clear()
    bonsai_layer.Proxy._vision = None   # ask /props again


def tool_turn():
    return [{"role": "user", "content": "Read the screenshot."},
            {"role": "assistant", "content": "", "tool_calls": [{"id": "t1", "type": "function",
             "function": {"name": "read", "arguments": "{\"path\": \"shot.png\"}"}}]},
            {"role": "tool", "tool_call_id": "t1", "content": [{"type": "text", "text": "Read image file"}, IMG]}]


def test_no_vision_chat():
    reset(False)
    body = {k: v for k, v in PLAIN.items() if k != "code_interpreter"}   # the default path (it reports a layer object)
    code, r = post("/v1/chat/completions", dict(body, messages=tool_turn(), max_tokens=40))
    assert code == 200 and r["choices"][0]["message"]["content"], (code, r)
    sent = json.dumps(S["bodies"][-1])
    assert '"image_url"' not in sent and bonsai_layer.NO_VISION_NOTE in sent, sent[:400]
    assert r.get("layer", {}).get("images_removed") == 1, r.get("layer")
    print("no vision, chat: the image becomes the note, the turn answers: ok")


def test_vision_kept():
    reset(True)
    code, r = post("/v1/chat/completions", dict(PLAIN, messages=tool_turn(), max_tokens=40))
    assert code == 200 and '"image_url"' in json.dumps(S["bodies"][-1]), (code, r)
    print("vision on: the image goes to the server unchanged: ok")


def test_no_vision_responses():
    reset(False)
    body = {"model": "m", "input": [{"role": "user", "content": [{"type": "input_text", "text": "What is this?"},
                                                                {"type": "input_image", "image_url": "data:image/png;base64,iVBO"}]}]}
    code, r = post("/v1/responses", body)
    sent = json.dumps(S["bodies"][-1])
    assert code == 200 and '"input_image"' not in sent and bonsai_layer.NO_VISION_NOTE in sent, (code, sent[:300])
    print("no vision, Responses: input_image becomes input_text with the note: ok")


def test_no_image_unchanged():
    reset(False)
    msgs = [{"role": "user", "content": "Hello"}]
    code, r = post("/v1/chat/completions", dict(PLAIN, messages=msgs, max_tokens=10))
    assert code == 200 and S["bodies"][-1]["messages"][-1]["content"] == "Hello", S["bodies"][-1]
    assert "images_removed" not in (r.get("layer") or {}), r.get("layer")
    print("no image: the request is unchanged: ok")


if __name__ == "__main__":
    test_no_vision_chat()
    test_vision_kept()
    test_no_vision_responses()
    test_no_image_unchanged()
    print("ALL OK")
