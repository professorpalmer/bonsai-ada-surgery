"""release-20261022 R3 (the note): requests through the layer; the caller counts the layer.log lines after each."""
import json
import sys
import time
import urllib.request

KEY = open(sys.argv[1]).read().strip()
LOG = sys.argv[2]


def lines():
    try:
        return sum(1 for l in open(LOG, encoding="utf-8", errors="replace") if "approximate-length note on" in l)
    except OSError:
        return 0


def ask(text, **extra):
    body = dict({"messages": [{"role": "user", "content": text}]}, **extra)
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    before = lines()
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            code, out = r.status, json.load(r)
    except urllib.error.HTTPError as e:
        code, out = e.code, {}
    time.sleep(1)
    msg = out["choices"][0]["message"] if code == 200 else {}
    return code, len((msg.get("content") or "").split()), lines() - before, round(time.time() - t0, 1)


for label, text, extra in [("story 300 words", "Write a 300-word short story about a fox.", {}),
                           ("poem 40 lines", "Write a 40-line poem about rain.", {}),
                           ("story, approx_note false", "Write a 300-word short story about a fox.", {"approx_note": False})]:
    code, words, new_lines, s = ask(text, **extra)
    print(f"note {label}: HTTP {code}, {words} words, {s} s, new note lines in layer.log: {new_lines}")
