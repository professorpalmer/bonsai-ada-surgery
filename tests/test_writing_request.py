"""Offline test: the layer does not offer run_python to writing requests (docs/research/story-think-20261021, G5), and
still offers it to code and other requests. The first user message decides.
python tests/test_writing_request.py
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

PROMPTS = json.load(open(os.path.join(ROOT, "docs", "research", "story-think-20261021", "prompts.json"), encoding="utf-8"))
S = {"bodies": []}
fails = 0


def check(name, ok, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + (": " + detail if detail and not ok else ""))
    fails += 0 if ok else 1


# 1. The pattern, on the study's chat prompts and on requests that must keep the tool.
for p in PROMPTS:
    if not p["tools"]:
        check("writing: " + p["id"], bonsai_layer.writing_request([{"role": "user", "content": p["text"]}]))
for text in ["Write a Python function that returns the n-th prime.", "Write a script that tells a story about a cat.",
             "What is 17 * 23?", "Fix the bug in this code:\n```\nprint(x\n```",
             "How many words are in this sentence?",
             # review of #227: counting and data tasks keep the tool
             "Tell me how many times the letter r appears in strawberry.",
             "Give each student a letter grade: Ann 87, Bo 72, Cy 95.",
             "Write a letter frequency table for this text: the quick brown fox.",
             "Make a song list sorted by duration: A 3:10, B 2:45, C 4:01.",
             "Give me a summary of this article with the word counts.",
             "Make a speech timer estimate: 130 wpm, 1,950 words.",
             "Compute the mean of these numbers: 4, 8, 15.\n" + "x " * 200 + "She would tell her grandson the story again."]:
    check("not writing: " + text[:40].replace("\n", " "), not bonsai_layer.writing_request([{"role": "user", "content": text}]))
for text in ["Generate a short story about a fox.", "Produce a poem for my mother's birthday."]:
    check("writing: " + text[:40], bonsai_layer.writing_request([{"role": "user", "content": text}]))
# Known limitation (the safe direction: the old behaviour, the tool is offered): a code noun anywhere in the message.
check("known limitation: 'app' keeps the tool", not bonsai_layer.writing_request(
    [{"role": "user", "content": "Write a story about a phone app."}]))
check("the first user message decides", bonsai_layer.writing_request([
    {"role": "system", "content": "You are helpful."}, {"role": "user", "content": "Write a poem about rain."},
    {"role": "assistant", "content": "..."}, {"role": "user", "content": "Now compute 2**100."}]))
check("list content", bonsai_layer.writing_request([{"role": "user", "content": [{"type": "text", "text": "Tell me a story."}]}]))


# 2. End to end through the layer: what the server receives.
class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        out = json.dumps({"modalities": {"vision": False}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_POST(self):
        S["bodies"].append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        out = json.dumps({"object": "chat.completion", "choices": [{"index": 0, "finish_reason": "stop",
                          "message": {"role": "assistant", "content": "Done."}}],
                          "usage": {"prompt_tokens": 10, "completion_tokens": 2, "total_tokens": 12}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)


up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
bonsai_layer.Proxy.upstream = f"http://127.0.0.1:{up.server_address[1]}"
bonsai_layer.Proxy.api_key = None
bonsai_layer.Proxy.slots = None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), bonsai_layer.Proxy)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_address[1]}"


def tools_sent(text, **extra):
    S["bodies"].clear()
    body = dict({"messages": [{"role": "user", "content": text}], "max_tokens": 20}, **extra)
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=30).read()
    return [t["function"]["name"] for t in (S["bodies"][-1].get("tools") or [])]


check("story: no run_python sent", tools_sent("Write a 1,500-word short story about a lighthouse.") == [])
check("story, streamed: no run_python sent", tools_sent("Tell me a long story.", stream=True) == [])
check("code: run_python sent", bonsai_layer.TOOL_NAME in tools_sent("What is the sum of the first 1000 primes?"))
check("story with code_interpreter true: run_python sent",
      bonsai_layer.TOOL_NAME in tools_sent("Write a poem about rain.", code_interpreter=True))
print("ALL PASS" if not fails else "%d FAIL" % fails)
sys.exit(1 if fails else 0)
