"""Write once: arms M (default), P (plan call, then continue from the plan), C (cut the thinking at the draft, then
continue). python wo_ab.py INNER KEYFILE OUTDIR   (INNER: llama-server). Plan and gates: README.md."""
import json
import os
import re
import sys
import time
import urllib.request

INNER, KEYFILE, OUT = sys.argv[1:4]
KEY = open(KEYFILE).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import draft_detect  # noqa: E402

PROMPTS = json.load(open(os.path.join(HERE, "prompts.json"), encoding="utf-8"))
SEEDS = [5, 6, 7]
ARMS = ["M", "P", "C"]
SYS = {"role": "system", "content": "You are a helpful assistant."}
PLAN_ASK = ("\n\n(Planning step: write a short plan only, at most 150 words: the main idea, the people, the shape, the "
            "tone and the length. Do not write the text itself.)")
WRITE_FILE = {"type": "function", "function": {
    "name": "write_file", "description": "Write a text file in the workspace.",
    "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                   "required": ["path", "content"]}}}
HDR = {"Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
os.makedirs(os.path.join(OUT, "texts"), exist_ok=True)


def post(body, timeout=1800):
    req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(body).encode(), headers=HDR)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def shingles(t, n=8):
    w = re.findall(r"[a-z0-9']+", (t or "").lower())
    return {" ".join(w[i:i + n]) for i in range(len(w) - n + 1)}


def dup(final, think):
    a = shingles(final)
    return round(len(a & shingles(think)) / len(a), 3) if a else 0.0


def base(p, seed):
    body = {"messages": [SYS, {"role": "user", "content": p["text"]}], "seed": seed}
    if p["tools"]:
        body["tools"] = [WRITE_FILE]
    return body


def parse_msg(out):
    ch = (out.get("choices") or [{}])[0]
    return ch.get("message") or {}, ch.get("finish_reason")


def final_of(msg):
    for c in msg.get("tool_calls") or []:
        f = c.get("function") or {}
        if f.get("name") == "write_file":
            try:
                return json.loads(f.get("arguments") or "{}").get("content") or "", True
            except ValueError:
                return "", True
    return msg.get("content") or "", False


def continue_from(p, seed, plan):
    body = base(p, seed)
    body["messages"] = body["messages"] + [{"role": "assistant", "reasoning_content": plan, "content": ""}]
    body["continue_final_message"] = "content"
    body["add_generation_prompt"] = False
    return post(body)


def stream_until_draft(p, seed):
    """Stream the real request; close it at the first draft paragraph of the thinking. Returns (thinking so far,
    cut index or None, kind, message if it ended on its own, finish)."""
    body = dict(base(p, seed), stream=True)
    req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(body).encode(), headers=HDR)
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
                if not content and not calls and think.count("\n\n") > checked:   # a paragraph ended: look
                    checked = think.count("\n\n")
                    cut = draft_detect.draft_start(think)
                    if cut is not None:
                        return think, cut, draft_detect.draft_kind(think), None, None
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
        r.close()   # closing the stream stops the generation on the server
    msg = {"reasoning_content": think, "content": content,
           "tool_calls": [{"function": {"name": c["name"], "arguments": c["arguments"]}} for _, c in sorted(calls.items())]}
    return think, None, None, msg, finish


def run(p, arm, seed):
    t0 = time.time()
    info = {}
    if arm == "M":
        msg, finish = parse_msg(post(base(p, seed)))
        think_all = msg.get("reasoning_content") or ""
    elif arm == "P":
        pb = base(p, seed)
        pb["messages"] = [SYS, {"role": "user", "content": p["text"] + PLAN_ASK}]
        pb.pop("tools", None)
        pb.update({"chat_template_kwargs": {"enable_thinking": False}, "max_tokens": 500})
        plan = (parse_msg(post(pb))[0].get("content") or "").strip()
        info = {"plan_words": words(plan), "plan_s": round(time.time() - t0, 1)}
        msg, finish = parse_msg(continue_from(p, seed, plan))
        think_all = plan + "\n" + (msg.get("reasoning_content") or "")
    else:
        think, cut, kind, msg, finish = stream_until_draft(p, seed)
        info = {"cut_kind": kind, "thinking_words_streamed": words(think)}
        if cut is not None:
            plan = think[:cut].rstrip()
            info.update({"plan_words": words(plan), "cut_s": round(time.time() - t0, 1)})
            msg, finish = parse_msg(continue_from(p, seed, plan))
            think_all = think + "\n" + (msg.get("reasoning_content") or "")
        else:
            think_all = think
    wall = round(time.time() - t0, 1)
    text, via = final_of(msg)
    content = msg.get("content") or ""
    e = dict({"prompt": p["id"], "arm": arm, "seed": seed, "wall_s": wall, "finish": finish,
              "thinking_words": words(think_all), "words": words(text), "requested_words": p["words"],
              "tools_prompt": p["tools"], "via_write_file": via, "dup": dup(text, think_all), "empty": not text.strip(),
              "claims_save": (not via) and bool(re.search(r"\b(saved|wrote|written)\b[^.]{0,60}\b(to|in|into|as)\b[^.]{0,40}\.(md|txt)\b", content, re.I)),
              "count_leak": bool(draft_detect.COUNTING.search(text))}, **info)
    open(os.path.join(OUT, "texts", f"{p['id']}_s{seed}_{arm}.md"), "w", encoding="utf-8").write(
        "## thinking\n\n" + think_all + "\n\n## final text\n\n" + text + "\n")
    return e


rpath = os.path.join(OUT, "runs.jsonl")
done = set()
if os.path.exists(rpath):
    for l in open(rpath, encoding="utf-8"):
        x = json.loads(l)
        done.add((x["prompt"], x["arm"], x["seed"]))
for seed in SEEDS:
    for p in PROMPTS:
        for arm in ARMS:
            if (p["id"], arm, seed) in done:
                continue
            try:
                e = run(p, arm, seed)
            except Exception as ex:   # noqa: BLE001
                e = {"prompt": p["id"], "arm": arm, "seed": seed, "error": repr(ex)[:300]}
            open(rpath, "a", encoding="utf-8").write(json.dumps(e) + "\n")
            print(json.dumps(e), flush=True)
print("done", flush=True)
