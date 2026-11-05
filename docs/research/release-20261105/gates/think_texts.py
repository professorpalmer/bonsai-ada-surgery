"""R5 texts with thinking on: greedy replies (0073 acts only while the think block is open), one file per prompt.
    python think_texts.py --base http://127.0.0.1:8080 --key-file <root>/artifacts/api_key.txt --out <dir>
Each file holds finish, reasoning and content; compare two output folders with --compare <dirA> <dirB>."""
import argparse
import json
import os
import sys
import urllib.request

PROMPTS = [
    ("train", "A train leaves at 09:40 and the trip takes 2 h 55 min. When does it arrive? Check your arithmetic."),
    ("code", "Write a Python function that merges overlapping intervals given as a list of [start, end] pairs. "
             "Include two short tests."),
    ("prose", "Explain in one paragraph why the sky is blue, for a ten-year-old."),
    ("bash", "Write a bash one-liner that prints the 5 largest files under the current folder, with sizes."),
    ("logic", "Three boxes are labelled apples, oranges and mixed, and every label is wrong. You may take one fruit "
              "from one box. How do you fix all the labels?"),
    ("math", "What is the sum of the integers from 1 to 1000 that are divisible by 3 or 5?"),
]


def post(base, key, body):
    req = urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=1800) as r:
        return json.loads(r.read())


def compare(a, b):
    same = 0
    names = sorted(os.listdir(a))
    for n in names:
        x = json.load(open(os.path.join(a, n), encoding="utf-8"))
        y = json.load(open(os.path.join(b, n), encoding="utf-8"))
        if x == y:
            same += 1
        else:
            print(f"{n}: DIFFER (A finish {x['finish']}, answered {bool(x['content'].strip())}; "
                  f"B finish {y['finish']}, answered {bool(y['content'].strip())})")
    print(f"texts: {same} / {len(names)} identical")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--key-file")
    ap.add_argument("--out")
    ap.add_argument("--max-tokens", type=int, default=4096)
    ap.add_argument("--compare", nargs=2)
    a = ap.parse_args()
    if a.compare:
        return compare(*a.compare)
    key = open(a.key_file).read().strip()
    os.makedirs(a.out, exist_ok=True)
    for name, prompt in PROMPTS:
        r = post(a.base, key, {"messages": [{"role": "user", "content": prompt}], "max_tokens": a.max_tokens,
                               "temperature": 0})
        ch = r["choices"][0]
        m = ch["message"]
        row = {"finish": ch.get("finish_reason"), "reasoning": m.get("reasoning_content") or "",
               "content": m.get("content") or ""}
        with open(os.path.join(a.out, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(row, f, ensure_ascii=False, indent=1)
        print(f"{name}: finish {row['finish']}, reasoning {len(row['reasoning'])} chars, "
              f"content {len(row['content'])} chars", flush=True)


if __name__ == "__main__":
    sys.exit(main())
