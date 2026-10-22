"""No count: arm K (stream the thinking; at each word count close the stream and continue the thinking without it).
python nc_ab.py INNER KEYFILE OUTDIR. Plan and gates: README.md. M: ../write-once-20261022/runs.jsonl and texts/."""
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
MAX_CUTS = 6
NOCOUNT = "I will not count the words one by one: an approximate length is fine."
COUNT_START = re.compile(r"^\s*(let me count|let's count|count\s*:|word count|counting\b|recount)", re.I)
SYS = {"role": "system", "content": "You are a helpful assistant."}
WRITE_FILE = {"type": "function", "function": {
    "name": "write_file", "description": "Write a text file in the workspace.",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                   "required": ["path", "content"]}}}
HDR = {"Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
os.makedirs(os.path.join(OUT, "texts"), exist_ok=True)


BUDGET = 20480


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def ntok(text):
    req = urllib.request.Request(INNER + "/tokenize", data=json.dumps({"content": text}).encode(), headers=HDR)
    with urllib.request.urlopen(req, timeout=60) as r:
        return len(json.load(r).get("tokens", []))


def count_start(text):
    """Index of the first counting paragraph in text, or None."""
    for i, par in draft_detect._paragraphs(text):
        if draft_detect.COUNTING.search(par) or COUNT_START.match(par):
            return i
    return None


def stream(body):
    """Stream one request. Returns (new reasoning, content, tool calls, finish, cut index in the new reasoning)."""
    req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(dict(body, stream=True)).encode(), headers=HDR)
    think, content, calls, finish, checked = "", "", {}, None, 0
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
                think += d["reasoning_content"]
                if body.get("_cuts_left", 1) > 0 and not content and not calls and think.count("\n\n") > checked:
                    checked = think.count("\n\n")
                    cut = count_start(think)
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
    kept, all_think, cuts, removed_words = "", "", 0, 0
    body = dict(base, _cuts_left=MAX_CUTS)
    while True:
        send = {k: v for k, v in body.items() if not k.startswith("_")}
        new, content, calls, finish, cut = stream(send)
        if kept and new.startswith(kept):   # the server may echo the given thinking first
            new = new[len(kept):]
        all_think += new
        if cut is None:
            kept += new
            break
        cuts += 1
        removed_words += words(new[cut:])
        kept = (kept + new[:cut]).rstrip() + "\n\n" + NOCOUNT + "\n\n"
        # each request starts its own thinking budget: carry what is left of the 20,480 (the server's budget)
        left = max(512, BUDGET - ntok(all_think))
        body = dict(base, messages=msgs + [{"role": "assistant", "reasoning_content": kept, "content": ""}],
                    continue_final_message="reasoning_content", add_generation_prompt=False,
                    reasoning_budget_tokens=left, _cuts_left=MAX_CUTS - cuts)
    wall = round(time.time() - t0, 1)
    via, text = False, content
    for c in calls.values():
        if c["name"] == "write_file":
            via = True
            try:
                text = json.loads(c["arguments"] or "{}").get("content") or ""
            except ValueError:
                text = ""
    e = {"prompt": p["id"], "arm": "K", "seed": seed, "wall_s": wall, "finish": finish, "cuts": cuts,
         "removed_words": removed_words, "thinking_words": words(all_think), "kept_thinking_words": words(kept),
         "words": words(text), "requested_words": p["words"], "tools_prompt": p["tools"], "via_write_file": via,
         "empty": not text.strip(), "budget_closed": "Now produce the complete answer" in all_think,
         "claims_save": (not via) and bool(re.search(r"\b(saved|wrote|written)\b[^.]{0,60}\b(to|in|into|as)\b[^.]{0,40}\.(md|txt)\b", content, re.I)),
         "count_leak": bool(draft_detect.COUNTING.search(text))}
    open(os.path.join(OUT, "texts", f"{p['id']}_s{seed}_K.md"), "w", encoding="utf-8").write(
        "## thinking\n\n" + kept + "\n\n## final text\n\n" + text + "\n")
    return e


rpath = os.path.join(OUT, "runs.jsonl")
done = set()
if os.path.exists(rpath):
    for l in open(rpath, encoding="utf-8"):
        x = json.loads(l)
        done.add((x["prompt"], x["seed"]))
for seed in SEEDS:
    for p in PROMPTS:
        if (p["id"], seed) in done:
            continue
        try:
            e = run(p, seed)
        except Exception as ex:   # noqa: BLE001
            e = {"prompt": p["id"], "arm": "K", "seed": seed, "error": repr(ex)[:300]}
        open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
        print(json.dumps(e), flush=True)
print("done", flush=True)
