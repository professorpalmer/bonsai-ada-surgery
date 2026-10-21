"""Writing requests 3: arms M and B2T (budget 2048 with a close message that names the tool call) on 8 prompts x 2 seeds, then a judge that counts only verdicts that agree in
both orders. python story_ab2.py BASE INNER KEYFILE OUTDIR   (BASE: the layer, INNER: llama-server for /tokenize)
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
CLOSE = ("Stop thinking now. Write the complete answer. If the request asks you to save or write a file, make that "
         "tool call now, with the complete text in it.")
ARMS = {"M": {}, "B2T": {"reasoning_budget_tokens": 2048, "reasoning_budget_message": CLOSE}}
SEEDS = [3, 4]
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
    return len(post(INNER + "/tokenize", {"content": text}).get("tokens", [])) if text else 0


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def shingles(t, n=8):
    w = re.findall(r"[a-z0-9']+", (t or "").lower())
    return {" ".join(w[i:i + n]) for i in range(len(w) - n + 1)}


def dup(final, think):
    a = shingles(final)
    return round(len(a & shingles(think)) / len(a), 3) if a else 0.0


def request(p, arm, seed):
    body = {"messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": p["text"]}],
            "seed": seed}
    if p["tools"]:
        body["tools"] = [WRITE_FILE]
    else:
        body["code_interpreter"] = False
    body.update(ARMS[arm])
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


def tpath(pid, arm, seed):
    return os.path.join(OUT, "texts", f"{pid}_s{seed}_{arm}.md")


rpath = os.path.join(OUT, "runs.jsonl")
done = set()
if os.path.exists(rpath):
    for l in open(rpath, encoding="utf-8"):
        e = json.loads(l)
        done.add((e["prompt"], e["arm"], e["seed"]))
for seed in SEEDS:
    for p in PROMPTS:
        for arm in ARMS:
            if (p["id"], arm, seed) in done:
                continue
            t0 = time.time()
            try:
                out, err = post(BASE + "/v1/chat/completions", request(p, arm, seed)), None
            except Exception as e:   # noqa: BLE001
                out, err = {}, repr(e)[:300]
            wall = round(time.time() - t0, 1)
            ch = (out.get("choices") or [{}])[0]
            msg = ch.get("message") or {}
            think = msg.get("reasoning_content") or ""
            text, via_tool = final_text(msg)
            e = {"prompt": p["id"], "arm": arm, "seed": seed, "wall_s": wall, "error": err, "finish": ch.get("finish_reason"),
                 "think_tokens": ntok(think), "completion_tokens": (out.get("usage") or {}).get("completion_tokens"),
                 "words": words(text), "requested_words": p["words"], "tools_prompt": p["tools"],
                 "via_write_file": via_tool, "budget_closed": ("Now produce the complete answer" in think) or ("Stop thinking now." in think),
                 "claims_save": (not via_tool) and bool(re.search(r"\b(saved|wrote|written)\b[^.]{0,60}\b(to|in|into|as)\b[^.]{0,40}\.(md|txt)\b", text, re.I)),
                 "dup": dup(text, think), "empty": not text.strip()}
            open(tpath(p["id"], arm, seed), "w", encoding="utf-8").write(
                "## thinking\n\n" + think + "\n\n## final text\n\n" + text + "\n")
            open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
            print(json.dumps(e), flush=True)

jpath = os.path.join(OUT, "judge.jsonl")
jdone = set()
if os.path.exists(jpath):
    for l in open(jpath, encoding="utf-8"):
        e = json.loads(l)
        jdone.add((e["prompt"], e["arm"], e["seed"], e["order"]))


def text_of(pid, arm, seed):
    return open(tpath(pid, arm, seed), encoding="utf-8").read().split("## final text\n\n", 1)[1].strip()


for seed in SEEDS:
    for p in PROMPTS:
        for arm in [a for a in ARMS if a != "M"]:
            for order in ("arm_first", "M_first"):
                if (p["id"], arm, seed, order) in jdone:
                    continue
                x, y = text_of(p["id"], arm, seed), text_of(p["id"], "M", seed)
                a, b = (x, y) if order == "arm_first" else (y, x)
                q = ("Two texts were written for this request:\n\n" + p["text"] + "\n\nText A:\n\n" + a + "\n\nText B:\n\n" + b +
                     "\n\nWhich text is better writing and follows the request better? Answer with one word: A, B or TIE.")
                out = post(INNER + "/v1/chat/completions", {"messages": [{"role": "user", "content": q}], "max_tokens": 8,
                                                            "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}})
                ans = (((out.get("choices") or [{}])[0]).get("message") or {}).get("content") or ""
                v = re.findall(r"\b(A|B|TIE)\b", ans.upper())
                v = v[0] if v else "?"
                res = "tie" if v == "TIE" else ("?" if v == "?" else ("arm" if (v == "A") == (order == "arm_first") else "M"))
                e = {"prompt": p["id"], "arm": arm, "seed": seed, "order": order, "verdict": v, "winner": res}
                open(jpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
                print(json.dumps(e), flush=True)
print("done", flush=True)
