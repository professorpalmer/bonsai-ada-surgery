"""A/B thinking modes against a running llama-server.

Killy's finding: medium closes the coding gap to the 27B teacher only when the generation
cap is >= 20k; a 10k cap makes medium worse than thinking off. This script measures the
mechanism on short tasks (SVG + one code prompt): thinking tokens vs whether content landed.

  python bench/reason_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request

SVG = [
    "five-tier pagoda",
    "Chinese dragon",
    "violin",
    "sitting cat",
]
CODE = (
    "Write a complete Python function `balanced(s: str) -> bool` that returns True iff the "
    "parentheses, brackets and braces in s are balanced. Include a 12-case pytest. Code only."
)


def headers(key):
    h = {"Content-Type": "application/json"}
    if key:
        h["Authorization"] = "Bearer " + key
    return h


def chat(base, key, prompt, kwargs, max_tokens, timeout=600):
    body = {
        "model": "bonsai-2-27b",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": max_tokens,
        "chat_template_kwargs": kwargs,
    }
    req = urllib.request.Request(
        base.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers=headers(key),
    )
    t0 = time.time()
    raw = urllib.request.urlopen(req, timeout=timeout).read()
    dt = time.time() - t0
    out = json.loads(raw)
    ch = (out.get("choices") or [{}])[0]
    msg = ch.get("message") or {}
    usage = out.get("usage") or {}
    details = usage.get("completion_tokens_details") or {}
    content = msg.get("content") or ""
    thinking = msg.get("reasoning_content") or msg.get("reasoning") or ""
    return {
        "s": round(dt, 1),
        "finish": ch.get("finish_reason"),
        "think_tok": details.get("reasoning_tokens", 0),
        "out_tok": usage.get("completion_tokens", 0),
        "content_n": len(content),
        "think_n": len(thinking),
        "has_svg": "<svg" in content.lower(),
        "has_def": "def balanced" in content,
        "empty": not content.strip(),
        "head": content[:80].replace("\n", " "),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", default="")
    ap.add_argument("--max-tokens", type=int, default=2048)
    args = ap.parse_args()
    key = open(args.key_file, encoding="utf-8").read().strip() if args.key_file else ""

    arms = [
        ("off", {"enable_thinking": False, "reasoning_effort": "medium"}),
        ("low", {"enable_thinking": True, "reasoning_effort": "low"}),
        ("medium", {"enable_thinking": True, "reasoning_effort": "medium"}),
        ("xhigh", {"enable_thinking": True, "reasoning_effort": "xhigh"}),
    ]
    rows = []
    for name, kwargs in arms:
        for subj in SVG:
            prompt = (
                f"Draw a {subj} as a single self-contained SVG. No markdown, no explanation, "
                "inline SVG only. Temperature-0 style: clean geometric shapes, white background."
            )
            rec = {"arm": name, "task": "svg:" + subj}
            try:
                rec.update(chat(args.base, key, prompt, kwargs, args.max_tokens))
            except Exception as e:
                rec["error"] = str(e)
            rows.append(rec)
            print(json.dumps(rec), flush=True)
        rec = {"arm": name, "task": "code:balanced"}
        try:
            rec.update(chat(args.base, key, CODE, kwargs, max(args.max_tokens, 4096)))
        except Exception as e:
            rec["error"] = str(e)
        rows.append(rec)
        print(json.dumps(rec), flush=True)

    print("\narm      empty  svg  code  mean_think_tok  mean_out_tok  mean_s")
    for name, _ in arms:
        mine = [r for r in rows if r["arm"] == name and "error" not in r]
        if not mine:
            continue
        n = len(mine)
        print(
            f"{name:<8} {sum(r['empty'] for r in mine):>5}  {sum(r['has_svg'] for r in mine):>3}  "
            f"{sum(r['has_def'] for r in mine):>4}  {sum(r['think_tok'] for r in mine)/n:14.0f}  "
            f"{sum(r['out_tok'] for r in mine)/n:12.0f}  {sum(r['s'] for r in mine)/n:6.1f}"
        )


if __name__ == "__main__":
    sys.exit(main())
