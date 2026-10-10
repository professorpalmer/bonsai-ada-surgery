"""Issue #16: system RAM under sequential long thinking requests. Each request has its own ~DEPTH-token preamble (no
shared prefix, so every new request moves the previous slot state and its checkpoints into the prompt cache), thinking
on, max_tokens 4096 like the report. Prints one JSON line per request; bench/ram_sample.ps1 records the memory.

python bench/ram_probe.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --n 7 --depth 24000 --tag A
"""
from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request

BUG = '''Find and fix the bug in this function, then explain the fix in a short paragraph.

def merge_intervals(xs):
    xs.sort()
    out = [xs[0]]
    for a, b in xs[1:]:
        if a < out[-1][1]:
            out[-1][1] = b
        else:
            out.append([a, b])
    return out
'''


def headers(key):
    return {"Content-Type": "application/json", **({"Authorization": "Bearer " + key} if key else {})}


def preamble(i, n_sent):
    subjects = ["the archive", "a survey", "the committee", "one report", "the ledger", "a memo", "the register", "field notes"]
    verbs = ["records", "lists", "mentions", "summarizes", "notes", "confirms", "tracks", "describes"]
    objects = ["shipments", "rainfall totals", "meeting dates", "inventory counts", "repair logs", "visitor numbers",
               "budget lines", "soil samples", "route changes", "maintenance windows"]
    s = " ".join(f"{subjects[(k + i) % 8].capitalize()} {verbs[(k // 8 + i) % 8]} {objects[(k // 64 + i) % 10]} for entry {k}-{i}."
                 for k in range(n_sent))
    return f"Request {i}. Background notes (ignore them, answer the task at the end): {s}\n\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file")
    ap.add_argument("--n", type=int, default=7)
    ap.add_argument("--depth", type=int, default=24000)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    key = open(a.key_file).read().strip() if a.key_file else None
    for i in range(a.n):
        body = {"model": "b", "messages": [{"role": "user", "content": preamble(i, a.depth // 13) + BUG}],
                "max_tokens": 4096, "temperature": 0.6}
        req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=headers(key))
        t0 = time.time()
        rec = {"tag": a.tag, "i": i, "t0": time.strftime("%H:%M:%S")}
        try:
            r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
            t = r.get("timings", {})
            rec.update(status=200, prompt_n=t.get("prompt_n"), predicted_n=t.get("predicted_n"),
                       finish=r["choices"][0].get("finish_reason"))
        except urllib.error.HTTPError as e:
            rec.update(status=e.code, error=e.read().decode(errors="replace")[:200])
        except Exception as e:  # connection refused = the server died
            rec.update(status=0, error=repr(e)[:200])
        rec["wall_s"] = round(time.time() - t0, 1)
        print(json.dumps(rec), flush=True)
        if rec["status"] == 0:
            break


if __name__ == "__main__":
    main()
