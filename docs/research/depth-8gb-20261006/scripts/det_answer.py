"""Determinism probe (P146): one quick_tps 'code' prompt at a depth; saves the answer bytes and their sha256.

python det_answer.py --base URL --key-file F --depth 128000 --out answer.txt
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.request

sys.path.insert(0, r"C:\bonsai\bonsai-ada-surgery\bench")
import quick_tps as q  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", default=None)
ap.add_argument("--depth", type=int, required=True)
ap.add_argument("--out", required=True)
a = ap.parse_args()
key = open(a.key_file).read().strip() if a.key_file else None
name, prompt, n = q.PROMPTS[0]
body = {"model": "b", "messages": [{"role": "user", "content": q.filler(a.base, key, a.depth) + prompt}],
        "max_tokens": n, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=q._headers(key))
r = json.loads(urllib.request.urlopen(req, timeout=int(os.environ.get("QTPS_TIMEOUT", "7200"))).read())
text = r["choices"][0]["message"].get("content") or ""
raw = text.encode("utf-8")
open(a.out, "wb").write(raw)
t = r.get("timings", {})
print(f"det depth {a.depth} (evaluated {t.get('prompt_n')}): decode {t.get('predicted_per_second', 0):6.1f} tok/s "
      f"({t.get('predicted_n')} tok) answer {len(raw)} B sha256 {hashlib.sha256(raw).hexdigest()}", flush=True)
