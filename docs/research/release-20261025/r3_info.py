"""release-20261025 R3 (new): the forwarded answer reports the layer's changes."""
import json
import sys
import urllib.request

KEY = open(sys.argv[1]).read().strip()


def ask(text, **extra):
    body = dict({"messages": [{"role": "user", "content": text}]}, **extra)
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.status, json.load(r)


code, out = ask("Write a 300-word short story about an owl.")
print(f"info story: HTTP {code}, layer = {out.get('layer')!r}, approx_notes = {(out.get('layer') or {}).get('approx_notes')}")
code, out = ask("Write a 40-line poem about snow.", code_interpreter=False)
print(f"info poem: HTTP {code}, layer object present: {'layer' in out}")
