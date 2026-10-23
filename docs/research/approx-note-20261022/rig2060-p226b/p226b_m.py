"""P226b (#233): M only, seeds 5-7, prompts p1 / p4 / p6 / p10 (the 4070 M cells with 9-15k thinking words): does the
2060 reproduce the long count-heavy thinking on the same seeds? A copy of apc_ab.py with those 4 changes."""
"""Amendment A' confirmation: arms M and A' on the 7 prompts that get the note under A', seeds 8 and 9, in the order M,
A' for each prompt. python apc_ab.py INNER KEYFILE OUTDIR. Plan: README.md (amendment A')."""
import json
import os
import re
import sys
import time
import urllib.request

INNER, KEYFILE, OUT = sys.argv[1:4]
KEY = open(KEYFILE).read().strip()
HERE = "C:/bonsai/bas-apc/docs/research/approx-note-20261022"
sys.path.insert(0, os.path.join(HERE, "..", "write-once-20261022"))
import draft_detect  # noqa: E402

PROMPTS = json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))
SEEDS = [5, 6, 7]
LENGTH_RE = re.compile(r"\b(\d[\d,.]*)\s*(k?)\s*-?\s*(words?|tokens?)\b", re.I)
MAX_LEN = 10000
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


def gets_note(text):
    m = LENGTH_RE.search(text)
    if not m:
        return False
    n = float(m.group(1).replace(",", "")) * (1000 if m.group(2) else 1)
    return n <= MAX_LEN


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def run(p, arm, seed):
    user = p["text"] + (NOTE if arm == "A2" else "")
    body = {"messages": [SYS, {"role": "user", "content": user}], "seed": seed}
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
    e = {"prompt": p["id"], "arm": arm, "seed": seed, "wall_s": wall, "finish": ch.get("finish_reason"),
         "thinking_words": words(think), "numbered_words": len(NUMBERED.findall(think)), "words": words(text),
         "requested_words": p["words"], "tools_prompt": p["tools"], "via_write_file": via, "empty": not text.strip(),
         "budget_closed": "Now produce the complete answer" in think,
         "claims_save": (not via) and bool(re.search(r"\b(saved|wrote|written)\b[^.]{0,60}\b(to|in|into|as)\b[^.]{0,40}\.(md|txt)\b", content, re.I)),
         "count_leak": bool(draft_detect.COUNTING.search(text))}
    open(os.path.join(OUT, "texts", f"{p['id']}_s{seed}_{arm}.md"), "w", encoding="utf-8").write(
        "## thinking\n\n" + think + "\n\n## final text\n\n" + text + "\n")
    return e


rpath = os.path.join(OUT, "runs.jsonl")
done = set()
if os.path.exists(rpath):
    for l in open(rpath, encoding="utf-8"):
        x = json.loads(l)
        done.add((x["prompt"], x["arm"], x["seed"]))
for seed in SEEDS:
    for p in PROMPTS:
        if p["id"] not in ("p1_story", "p4_blog", "p6_save_story", "p10_save_long"):
            continue
        for arm in ("M",):
            if (p["id"], arm, seed) in done:
                continue
            try:
                e = run(p, arm, seed)
            except Exception as ex:   # noqa: BLE001
                e = {"prompt": p["id"], "arm": arm, "seed": seed, "error": repr(ex)[:300]}
            open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
            print(json.dumps(e), flush=True)
print("done", flush=True)
