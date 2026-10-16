"""Offline check of the edit repair in the layer (S3a wiring): a fake upstream returns an edit call whose old text has
the wrong indentation; the layer runs with --edit-repair and must return the call with the file's indentation, in the
non-streamed and the streamed form. Also checks that the request field "edit_repair": false turns it off.
    python bench/edit_repair_layer_test.py
"""
import http.server, json, os, socket, subprocess, sys, threading, time, urllib.request

FILE = "def f(x):\n    if x:\n        return 1\n    return 0\n"
BAD = {"path": "a.py", "oldText": "if x:\n    return 1", "newText": "if x:\n    return 2"}
GOOD_OLD = "    if x:\n        return 1"
GOOD_NEW = "    if x:\n        return 2"
CALL = {"id": "c1", "type": "function", "function": {"name": "edit", "arguments": json.dumps(BAD)}}


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


class Up(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if body.get("stream"):
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
            args = CALL["function"]["arguments"]
            evs = [{"choices": [{"index": 0, "delta": {"reasoning_content": "think"}}]},
                   {"choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": "c1", "type": "function",
                                                                       "function": {"name": "edit", "arguments": args[:20]}}]}}]},
                   {"choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "function": {"arguments": args[20:]}}]}}]},
                   {"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]}]
            for ev in evs:
                self.wfile.write(("data: " + json.dumps(ev) + "\n\n").encode()); self.wfile.flush(); time.sleep(0.05)
            self.wfile.write(b"data: [DONE]\n\n")
            return
        out = json.dumps({"choices": [{"index": 0, "message": {"role": "assistant", "content": "", "tool_calls": [json.loads(json.dumps(CALL))]},
                                       "finish_reason": "tool_calls"}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(out)))
        self.end_headers(); self.wfile.write(out)


up_port, layer_port = free_port(), free_port()
srv = http.server.ThreadingHTTPServer(("127.0.0.1", up_port), Up)
threading.Thread(target=srv.serve_forever, daemon=True).start()
here = os.path.dirname(os.path.abspath(__file__))
layer = subprocess.Popen([sys.executable, os.path.join(here, "..", "layer", "bonsai_layer.py"), "--port", str(layer_port),
                          "--upstream", f"http://127.0.0.1:{up_port}", "--edit-repair", "--no-cards", "--no-lint"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    for _ in range(50):
        try:
            socket.create_connection(("127.0.0.1", layer_port), 0.2).close(); break
        except OSError:
            time.sleep(0.1)
    req_body = {"model": "m", "tools": [{"type": "function", "function": {"name": "edit", "parameters": {"type": "object"}}}],
                "messages": [{"role": "user", "content": "fix a.py"}, {"role": "tool", "tool_call_id": "c0", "content": FILE}]}

    def post(extra):
        b = dict(req_body, **extra)
        r = urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{layer_port}/v1/chat/completions",
                                   data=json.dumps(b).encode(), headers={"Content-Type": "application/json"}), timeout=30)
        return r.read().decode()

    fails = 0
    def check(name, args, want_old, want_new):
        global fails
        ok = args.get("oldText") == want_old and args.get("newText") == want_new
        fails += not ok
        print(("PASS " if ok else "FAIL ") + name, "" if ok else args)

    resp = json.loads(post({}))
    check("non-stream repaired", json.loads(resp["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"]), GOOD_OLD, GOOD_NEW)
    print("     layer info:", resp.get("layer"))
    resp = json.loads(post({"edit_repair": False}))
    check("non-stream off by request", json.loads(resp["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"]), BAD["oldText"], BAD["newText"])

    def stream_args(extra):
        text = post(dict(extra, stream=True))
        args, order = "", []
        for line in text.splitlines():
            if not line.startswith("data: ") or line == "data: [DONE]":
                if line == "data: [DONE]": order.append("done")
                continue
            ev = json.loads(line[6:])
            for ch in ev.get("choices") or []:
                d = ch.get("delta") or {}
                if d.get("reasoning_content"): order.append("reasoning")
                for c in d.get("tool_calls") or []:
                    order.append("tool"); args += (c.get("function") or {}).get("arguments") or ""
                if ch.get("finish_reason"): order.append("finish")
        return json.loads(args), order

    args, order = stream_args({})
    check("stream repaired", args, GOOD_OLD, GOOD_NEW)
    print("     order:", order)
    fails += order != ["reasoning", "tool", "finish", "done"]
    args, order = stream_args({"edit_repair": False})
    check("stream off by request", args, BAD["oldText"], BAD["newText"])
    print("ALL PASS" if not fails else f"{fails} FAIL")
finally:
    layer.terminate(); srv.shutdown()
