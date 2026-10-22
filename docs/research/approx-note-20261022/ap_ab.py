"""Arm A: the approximate-length note on writing requests that name a length in words or tokens.
python ap_ab.py INNER KEYFILE OUTDIR. Plan and gates: README.md. M: ../write-once-20261022/runs.jsonl and texts/."""
import json
import os
import re
import sys
import time
import urllib.request

INNER, KEYFILE, OUT = sys.argv[1:4]
KEY = open(KEYFILE).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "write-once-20261022"))
import draft_detect  # noqa: E402

PROMPTS = json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))
SEEDS = [5, 6, 7]
LENGTH_RE = re.compile(r"\b\d[\d,.]*\s*k?\s*-?\s*(words?|tokens?)\b", re.I)
NOTE = ("\n\nAbout the length: an approximate length is fine. Do not count the words one by one, in your thinking or "
        "anywhere else.")
SYS = {"role": "system", "content": "You are a helpful assistant."}
WRITE_FILE = {"type": "function", "function": {
    "name": "write_file", "description": "Write a text file in the workspace.",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                   "required": ["path", "content"]}}}
HDR = {"Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
NUMBERED = re.compile(r"\b[A-Za-z'][\w'-]*\d{1,4}\b")
os.makedirs(os.path.join(OUT, "texts"), exist_ok=True)


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def run(p, seed):
    body = {"messages": [SYS, {"role": "user", "content": p["text"] + NOTE}], "seed": seed}
    if p["tools"]:
        body["tools"] = [WRITE_FILE]
    t0 = time.time()
    req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(body).encode(), headers=HDR)
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    wall = round(time.time() - t0, 1)
    ch = out["choices"][0]
    m = ch.get("message") or {}
    think, content = m.get("reasoning_content") or "", m.get("content") or ""
    via, text = False, content
    for c in m.get("tool_calls") or []:
        if (c.get("function") or {}).get("name") == "write_file":
            via = True
            try:
                text = json.loads(c["function"].get("arguments") or "{}").get("content") or ""
            except ValueError:
                text = ""
    e = {"prompt": p["id"], "arm": "A", "seed": seed, "wall_s": wall, "finish": ch.get("finish_reason"),
         "thinking_words": words(think), "numbered_words": len(NUMBERED.findall(think)), "words": words(text),
         "requested_words": p["words"], "tools_prompt": p["tools"], "via_write_file": via, "empty": not text.strip(),
         "budget_closed": "Now produce the complete answer" in think,
         "claims_save": (not via) and bool(re.search(r"\b(saved|wrote|written)\b[^.]{0,60}\b(to|in|into|as)\b[^.]{0,40}\.(md|txt)\b", content, re.I)),
         "count_leak": bool(draft_detect.COUNTING.search(text))}
    open(os.path.join(OUT, "texts", f"{p['id']}_s{seed}_A.md"), "w", encoding="utf-8").write(
        "## thinking\n\n" + think + "\n\n## final text\n\n" + text + "\n")
    return e


rpath = os.path.join(OUT, "runs.jsonl")
done = set()
if os.path.exists(rpath):
    for l in open(rpath, encoding="utf-8"):
        x = json.loads(l)
        done.add((x["prompt"], x["seed"]))
for seed in SEEDS:
    for p in PROMPTS:
        if not LENGTH_RE.search(p["text"]) or (p["id"], seed) in done:
            continue
        try:
            e = run(p, seed)
        except Exception as ex:   # noqa: BLE001
            e = {"prompt": p["id"], "arm": "A", "seed": seed, "error": repr(ex)[:300]}
        open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
        print(json.dumps(e), flush=True)
print("done", flush=True)
