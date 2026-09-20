"""Quick decode/prefill check against a running llama-server (uses the server's own timings field).

python bench/quick_tps.py --base http://127.0.0.1:8899 --key-file artifacts/api_key.txt [--depth 32000]
--depth pads the prompt with filler text to roughly that many tokens to measure speed at context depth.
"""
from __future__ import annotations

import argparse
import json
import urllib.request

PROMPTS = [
    ("code", "Write a 300-line Python module implementing an LRU cache with tests. Code only.", 400),
    ("prose", "Write a detailed 800 word essay on the history of the transistor.", 400),
    ("bash", "Write a bash script that rotates logs in /var/log with size and age limits, with comments.", 400),
]


def _headers(key):
    return {"Content-Type": "application/json", **({"Authorization": "Bearer " + key} if key else {})}


def n_tokens(base, key, text):
    req = urllib.request.Request(base.rstrip("/") + "/tokenize", data=json.dumps({"content": text}).encode(), headers=_headers(key))
    return len(json.loads(urllib.request.urlopen(req, timeout=600).read())["tokens"])


_FILLER_CACHE: dict = {}


def filler(base, key, target_tokens):
    """A bland preamble of about target_tokens tokens, sized with the server's own tokenizer.
    Varied sentences (not a repeated pattern) so the measurement is not a best case for KV/prefix tricks."""
    if target_tokens in _FILLER_CACHE:
        return _FILLER_CACHE[target_tokens]
    subjects = ["the archive", "a survey", "the committee", "one report", "the ledger", "a memo", "the register", "field notes"]
    verbs = ["records", "lists", "mentions", "summarizes", "notes", "confirms", "tracks", "describes"]
    objects = ["shipments", "rainfall totals", "meeting dates", "inventory counts", "repair logs", "visitor numbers",
               "budget lines", "soil samples", "route changes", "maintenance windows"]
    def sentence(i):
        return f"{subjects[i % 8].capitalize()} {verbs[(i // 8) % 8]} {objects[(i // 64) % 10]} for entry {i}."
    # ~12 tokens per sentence to start, then correct once with a real count
    n = max(1, target_tokens // 12)
    text = " ".join(sentence(i) for i in range(n))
    got = n_tokens(base, key, text)
    n = max(1, int(n * target_tokens / max(1, got)))
    text = " ".join(sentence(i) for i in range(n))
    _FILLER_CACHE[target_tokens] = "Background notes (ignore them, answer the question at the end): " + text + "\n\n"
    return _FILLER_CACHE[target_tokens]


def go(base, key, prompt, n, filler_tokens=0):
    if filler_tokens:
        prompt = filler(base, key, filler_tokens) + prompt
    body = {
        "model": "b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": n,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
    r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
    t = r.get("timings", {})
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8899")
    ap.add_argument("--key-file", default=None)
    ap.add_argument("--depth", type=int, default=0)
    a = ap.parse_args()
    key = open(a.key_file).read().strip() if a.key_file else None
    go(a.base, key, "Say hi.", 8)
    tg = []
    for name, p, n in PROMPTS:
        t = go(a.base, key, p, n, a.depth)
        tg.append(t.get("predicted_per_second") or 0)
        # prompt_n is what the server actually evaluated; after the first prompt at a depth the shared
        # filler is served from the prompt cache, so prefill/ttft are meaningful on the first line only
        print(f"{name:<6} depth {a.depth:>6} (evaluated {t.get('prompt_n')}): prefill {t.get('prompt_per_second', 0):7.1f} tok/s  "
              f"ttft {t.get('prompt_ms', 0)/1000:6.2f}s  decode {t.get('predicted_per_second', 0):6.1f} tok/s "
              f"({t.get('predicted_n')} tok)", flush=True)
    print(f"mean decode {sum(tg)/len(tg):.1f} tok/s")


if __name__ == "__main__":
    main()
