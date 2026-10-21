"""Writing requests: five arms (M default, L low, O thinking off, B budget 2048, N a note), then a pairwise judge.
python story_ab.py BASE INNER KEYFILE OUTDIR   (BASE: the layer, INNER: llama-server for /tokenize)
Plan and gates: README.md (declared before the runs)."""
import json
import os
import re
import sys
import time
import urllib.request

BASE, INNER, KEYFILE, OUT = sys.argv[1:5]
KEY = open(KEYFILE).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
PROMPTS = json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))
ARMS = ["M", "L", "O", "B", "N"]
NOTE = "Plan briefly in your thinking. Do not write the text itself in your thinking: write it once, in your answer."
WRITE_FILE = {"type": "function", "function": {
    "name": "write_file", "description": "Write a text file in the workspace.",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                   "required": ["path", "content"]}}}
os.makedirs(os.path.join(OUT, "texts"), exist_ok=True)


def post(url, body, timeout=1800):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={
        "Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def ntok(text):
    if not text:
        return 0
    return len(post(INNER + "/tokenize", {"content": text}).get("tokens", []))


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def shingles(t, n=8):
    w = re.findall(r"[a-z0-9']+", (t or "").lower())
    return {" ".join(w[i:i + n]) for i in range(len(w) - n + 1)}


def dup(final, think):
    a = shingles(final)
    return round(len(a & shingles(think)) / len(a), 3) if a else 0.0


def request(p, arm):
    user = p["text"] + ((" " + NOTE) if arm == "N" else "")
    body = {"messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": user}],
            "seed": 1}
    if p["tools"]:
        body["tools"] = [WRITE_FILE]
    if arm == "L":
        body["reasoning_effort"] = "low"
    if arm == "O":
        body["chat_template_kwargs"] = {"enable_thinking": False}
    if arm == "B":
        body["reasoning_budget_tokens"] = 2048
    return body


def final_text(msg):
    for c in msg.get("tool_calls") or []:
        f = c.get("function") or {}
        if f.get("name") == "write_file":
            try:
                return json.loads(f.get("arguments") or "{}").get("content") or "", True
            except ValueError:
                return "", True
    return msg.get("content") or "", False


runs = {}
rpath = os.path.join(OUT, "runs.jsonl")
if os.path.exists(rpath):   # resume: keep finished cells
    for l in open(rpath, encoding="utf-8"):
        e = json.loads(l)
        runs[(e["prompt"], e["arm"])] = e
for p in PROMPTS:
    for arm in ARMS:
        if (p["id"], arm) in runs:
            continue
        t0 = time.time()
        try:
            out = post(BASE + "/v1/chat/completions", request(p, arm))
            err = None
        except Exception as e:   # noqa: BLE001
            out, err = {}, repr(e)[:300]
        wall = round(time.time() - t0, 1)
        msg = ((out.get("choices") or [{}])[0]).get("message") or {}
        think = msg.get("reasoning_content") or ""
        text, via_tool = final_text(msg)
        e = {"prompt": p["id"], "arm": arm, "wall_s": wall, "error": err,
             "finish": ((out.get("choices") or [{}])[0]).get("finish_reason"),
             "think_tokens": ntok(think), "completion_tokens": (out.get("usage") or {}).get("completion_tokens"),
             "words": words(text), "requested_words": p["words"], "via_write_file": via_tool,
             "budget_closed": "Now produce the complete answer" in think,
             "dup": dup(text, think), "empty": not text.strip()}
        open(os.path.join(OUT, "texts", f"{p['id']}_{arm}.md"), "w", encoding="utf-8").write(
            "## thinking\n\n" + think + "\n\n## final text\n\n" + text + "\n")
        open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
        runs[(p["id"], arm)] = e
        print(json.dumps(e), flush=True)

# The judge: each arm against M, both orders, thinking off, temperature 0.
jpath = os.path.join(OUT, "judge.jsonl")
done = set()
if os.path.exists(jpath):
    for l in open(jpath, encoding="utf-8"):
        e = json.loads(l)
        done.add((e["prompt"], e["arm"], e["order"]))


def text_of(pid, arm):
    t = open(os.path.join(OUT, "texts", f"{pid}_{arm}.md"), encoding="utf-8").read()
    return t.split("## final text\n\n", 1)[1].strip()


for p in PROMPTS:
    for arm in ARMS[1:]:
        for order in ("arm_first", "M_first"):
            if (p["id"], arm, order) in done:
                continue
            x, y = (text_of(p["id"], arm), text_of(p["id"], "M"))
            a, b = (x, y) if order == "arm_first" else (y, x)
            q = ("Two texts were written for this request:\n\n" + p["text"] + "\n\nText A:\n\n" + a + "\n\nText B:\n\n" + b +
                 "\n\nWhich text is better writing and follows the request better? Answer with one word: A, B or TIE.")
            out = post(INNER + "/v1/chat/completions", {"messages": [{"role": "user", "content": q}], "max_tokens": 8,
                                                        "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}})
            ans = (((out.get("choices") or [{}])[0]).get("message") or {}).get("content") or ""
            v = re.findall(r"\b(A|B|TIE)\b", ans.upper())
            v = v[0] if v else "?"
            res = "tie" if v == "TIE" else ("?" if v == "?" else
                  ("arm" if (v == "A") == (order == "arm_first") else "M"))
            e = {"prompt": p["id"], "arm": arm, "order": order, "verdict": v, "winner": res}
            open(jpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
            print(json.dumps(e), flush=True)
print("done", flush=True)
