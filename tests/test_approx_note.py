"""Offline test: the approximate-length note (docs/research/approx-note-20261022) goes on writing requests that name a
length in words or tokens, once, on the same messages every turn; and the server gets it.
python tests/test_approx_note.py
"""
import http.server
import json
import os
import sys
import threading
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "layer"))
import bonsai_layer as L  # noqa: E402

NOTE = L.APPROX_NOTE
fails = 0


def check(name, ok, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok or not detail else ": " + detail))
    fails += 0 if ok else 1


def noted(text):
    return L.apply_approx_note([{"role": "user", "content": text}])[1] == 1


# 1. Which requests get the note.
for t in ["Write a 1,500-word short story about a lighthouse keeper.", "Write an 800-word blog post about balcony gardens.",
          "Write a 3,000-word short story and save it to bakers.md.", "Compose a 500 word essay on diaries.",
          "Write a 10,000-word novella chapter.", "Tell me a 2k token story."]:
    check("note: " + t[:40], noted(t))
for t in ["Great. tell me a 50k token story.", "Write a 20,000-word novella.",   # more than one reply holds (A')
          "Write a 40-line poem about an orchard.", "Tell me a long story.", "Write a 200-word Python docstring for this function.",
          "How many words are in a 1,500-word essay?", "Count the words in this 300-word text: ...",
          "Write a function that returns the first 100 words of a text."]:
    check("no note: " + t[:40], not noted(t))

# Review of the note PR: hard limits and short texts keep the count; decimal lengths are writing requests.
for t in ["Write a 6-word story.", "Write a story in exactly 100 words (a drabble).",
          "Write an essay of at most 650 words for my college application.",
          "Write a cover letter, no more than 250 words.", "Write a 300-word poem, strictly 300 words."]:
    check("no note (hard limit or short): " + t[:40], not noted(t))
for t in ["Write a 1.5k word story about a fox.", "Tell me a 2.5k token story."]:
    check("note (decimal length): " + t[:40], noted(t))
check("decimal length is a writing request (no run_python)",
      L.writing_request([{"role": "user", "content": "Write a 1.5k word story about a fox."}]))
parts = [{"role": "user", "content": [{"type": "text", "text": "Write a 1,500-word story about a fox."}]}]
pm, pn = L.apply_approx_note(parts)
check("list content gets the note as a text part", pn == 1 and pm[0]["content"][-1]["text"].endswith(NOTE))
check("list content: once", L.apply_approx_note(pm)[1] == 0)

# 2. Once, and the same on every turn.
m1 = [{"role": "system", "content": "s"}, {"role": "user", "content": "Write a 1,500-word story about a fox."}]
a, n = L.apply_approx_note(m1)
b, n2 = L.apply_approx_note(a)
check("applied once", n == 1 and n2 == 0 and a[1]["content"].count(NOTE) == 1)
turn2 = m1 + [{"role": "assistant", "content": "Here is the story..."}, {"role": "user", "content": "Now make it sadder."}]
t1, _ = L.apply_approx_note(m1)
t2, _ = L.apply_approx_note(turn2)
s1, s2 = L.prompt_summary({"messages": t1}), L.prompt_summary({"messages": t2})
check("turn 2 repeats turn 1's prompt (no prefix change)", L.prefix_change(s1, s2) is None, str(L.prefix_change(s1, s2)))
check("the writing test ignores the note ('count' in it)", L.writing_text(a[1]["content"]))


# 3. End to end: what the server receives.
class Fake(http.server.BaseHTTPRequestHandler):
    bodies = []

    def log_message(self, *a):
        pass

    def _send(self, obj):
        out = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_GET(self):
        self._send({"modalities": {"vision": False}})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Fake.bodies.append(body)
        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            ev = {"choices": [{"index": 0, "delta": {"content": "Done."}, "finish_reason": "stop"}]}
            self.wfile.write(b"data: " + json.dumps(ev).encode() + b"\n\ndata: [DONE]\n\n")
            return
        self._send({"object": "chat.completion", "choices": [{"index": 0, "finish_reason": "stop",
                    "message": {"role": "assistant", "content": "Done."}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}})


up = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=up.serve_forever, daemon=True).start()
L.Proxy.upstream = f"http://127.0.0.1:{up.server_address[1]}"
L.Proxy.api_key = None
L.Proxy.slots = None
L.Proxy.keepalive = 0
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), L.Proxy)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_address[1]}"
WF = {"type": "function", "function": {"name": "write_file", "parameters": {"type": "object", "properties": {}}}}


def sent_user(text, **extra):
    Fake.bodies.clear()
    body = dict({"messages": [{"role": "user", "content": text}], "max_tokens": 20}, **extra)
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=30).read()
    return Fake.bodies[-1]["messages"][-1]["content"], [t["function"]["name"] for t in Fake.bodies[-1].get("tools") or []]


c, tools = sent_user("Write a 1,500-word short story about a lighthouse.")
check("server gets the note", c.endswith(NOTE) and tools == [], f"{c[-60:]!r} {tools}")
r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(
    {"messages": [{"role": "user", "content": "Write a 1,500-word short story about a fox."}], "max_tokens": 20}).encode(),
    headers={"Content-Type": "application/json"}), timeout=30).read())
check("the answer reports the note (layer.approx_notes = 1)", (r.get("layer") or {}).get("approx_notes") == 1, str(r.get("layer")))
r = json.loads(urllib.request.urlopen(urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(
    {"messages": [{"role": "user", "content": "Write a 40-line poem about rain."}], "max_tokens": 20,
     "code_interpreter": False}).encode(), headers={"Content-Type": "application/json"}), timeout=30).read())
check("no change: the answer has no layer object", "layer" not in r, str(r.get("layer")))
c, _ = sent_user("Write a 1,500-word short story about a lighthouse.", stream=True)
check("streamed: server gets the note", c.endswith(NOTE))
c, tools = sent_user("Write a 1,500-word story and save it to story.md.", tools=[WF])
check("with client tools: server gets the note", c.endswith(NOTE) and tools == ["write_file"])
c, _ = sent_user("Write a 1,500-word short story about a lighthouse.", approx_note=False)
check("approx_note false: no note", NOTE not in c)
c, _ = sent_user("Write a 40-line poem about rain.")
check("a 40-line poem: no note", NOTE not in c)
print("ALL PASS" if not fails else "%d FAIL" % fails)
sys.exit(1 if fails else 0)
