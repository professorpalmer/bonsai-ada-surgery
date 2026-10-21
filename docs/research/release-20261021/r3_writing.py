"""release-20261021 R3: a writing request gets no run_python; a computation request still does."""
import json
import sys
import urllib.request

KEY = open(sys.argv[1]).read().strip()


def ask(text):
    body = {"messages": [{"role": "user", "content": text}]}
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, {}


code, out = ask("Write a 300-word short story about a fox.")
msg = out["choices"][0]["message"] if code == 200 else {}
words = len((msg.get("content") or "").split())
print(f"story: HTTP {code}, {words} words, interpreter_trace: {'interpreter_trace' in out} "
      f"({len(out.get('interpreter_trace') or [])} rounds)")
code, out = ask("What is the sum of the first 1000 primes?")
msg = out["choices"][0]["message"] if code == 200 else {}
c = (msg.get("content") or "")
print(f"primes: HTTP {code}, interpreter_trace: {'interpreter_trace' in out} ({len(out.get('interpreter_trace') or [])} rounds), "
      f"3,682,913 in answer: {'3682913' in c.replace(',', '')}; answer tail: {c[-120:]!r}")
