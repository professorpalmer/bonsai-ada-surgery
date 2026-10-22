"""Arm K2: stream the thinking; when it starts to count words one by one, close the stream, write the count for it
(count_oracle.answer, in the model's format) and continue the thinking, open, from there.
python k2_ab.py INNER KEYFILE OUTDIR [prompt_id:seed ...]   (no list: all 10 prompts x seeds 5, 6, 7)"""
import json
import os
import re
import sys
import time
import urllib.request

INNER, KEYFILE, OUT = sys.argv[1:4]
ONLY = [tuple(x.split(":")) for x in sys.argv[4:]]
KEY = open(KEYFILE).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "write-once-20261022"))
import count_oracle as O  # noqa: E402
import draft_detect  # noqa: E402

PROMPTS = json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))
SEEDS = [5, 6, 7]
MAX_ANSWERS = 40
BUDGET = 20480
SYS = {"role": "system", "content": "You are a helpful assistant."}
WRITE_FILE = {"type": "function", "function": {
    "name": "write_file", "description": "Write a text file in the workspace.",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                   "required": ["path", "content"]}}}
HDR = {"Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
os.makedirs(os.path.join(OUT, "texts"), exist_ok=True)


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def ntok(text):
    req = urllib.request.Request(INNER + "/tokenize", data=json.dumps({"content": text}).encode(), headers=HDR)
    with urllib.request.urlopen(req, timeout=60) as r:
        return len(json.load(r).get("tokens", []))


def stream(body, watch):
    """Stream one request. Returns (new reasoning, content, calls, finish, cut index in new reasoning or None)."""
    req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(dict(body, stream=True)).encode(), headers=HDR)
    think, content, calls, finish = "", "", {}, None
    r = urllib.request.urlopen(req, timeout=1800)
    try:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data: ") or line == "data: [DONE]":
                continue
            ev = json.loads(line[6:])
            ch = (ev.get("choices") or [{}])[0]
            d = ch.get("delta") or {}
            if d.get("reasoning_content"):
                prev = len(think)
                think += d["reasoning_content"]
                if watch and not content and not calls:
                    cut = O.count_start(think, max(0, prev - 80))
                    if cut is not None:
                        return think, content, calls, None, cut
            if d.get("content"):
                content += d["content"]
            for tc in d.get("tool_calls") or []:
                c = calls.setdefault(tc.get("index", 0), {"name": "", "arguments": ""})
                f = tc.get("function") or {}
                c["name"] += f.get("name") or ""
                c["arguments"] += f.get("arguments") or ""
            if ch.get("finish_reason"):
                finish = ch["finish_reason"]
    finally:
        r.close()
    return think, content, calls, finish, None


def run(p, seed):
    t0 = time.time()
    msgs = [SYS, {"role": "user", "content": p["text"]}]
    base = {"messages": msgs, "seed": seed}
    if p["tools"]:
        base["tools"] = [WRITE_FILE]
    kept, all_think, answers, so_far, body = "", "", 0, 0, dict(base)
    while True:
        new, content, calls, finish, cut = stream(body, answers < MAX_ANSWERS)
        if kept and new.startswith(kept):
            new = new[len(kept):]
        all_think += new
        if cut is None:
            kept += new
            break
        answers += 1
        text, so_far = O.answer(kept + new[:cut], so_far)
        kept = kept + new[:cut] + text + "\n"
        left = max(512, BUDGET - ntok(all_think))
        body = dict(base, messages=msgs + [{"role": "assistant", "reasoning_content": kept, "content": ""}],
                    continue_final_message="reasoning_content", add_generation_prompt=False,
                    reasoning_budget_tokens=left)
    wall = round(time.time() - t0, 1)
    via, text = False, content
    for c in calls.values():
        if c["name"] == "write_file":
            via = True
            try:
                text = json.loads(c["arguments"] or "{}").get("content") or ""
            except ValueError:
                text = ""
    e = {"prompt": p["id"], "arm": "K2", "seed": seed, "wall_s": wall, "finish": finish, "answers": answers,
         "thinking_words": words(all_think), "kept_thinking_words": words(kept), "words": words(text),
         "requested_words": p["words"], "tools_prompt": p["tools"], "via_write_file": via, "empty": not text.strip(),
         "budget_closed": "Now produce the complete answer" in all_think,
         "claims_save": (not via) and bool(re.search(r"\b(saved|wrote|written)\b[^.]{0,60}\b(to|in|into|as)\b[^.]{0,40}\.(md|txt)\b", content, re.I)),
         "count_leak": bool(draft_detect.COUNTING.search(text))}
    open(os.path.join(OUT, "texts", f"{p['id']}_s{seed}_K2.md"), "w", encoding="utf-8").write(
        "## thinking\n\n" + kept + "\n\n## final text\n\n" + text + "\n")
    return e


rpath = os.path.join(OUT, "runs.jsonl")
done = set()
if os.path.exists(rpath):
    for l in open(rpath, encoding="utf-8"):
        x = json.loads(l)
        done.add((x["prompt"], str(x["seed"])))
cells = ONLY or [(p["id"], str(s)) for s in SEEDS for p in PROMPTS]
byid = {p["id"]: p for p in PROMPTS}
for pid, seed in cells:
    if (pid, seed) in done:
        continue
    try:
        e = run(byid[pid], int(seed))
    except Exception as ex:   # noqa: BLE001
        e = {"prompt": pid, "arm": "K2", "seed": int(seed), "error": repr(ex)[:300]}
    open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
    print(json.dumps(e), flush=True)
print("done", flush=True)
