"""H7: thinking-budget closure mechanism, emulated client-side on raw /completion (token-level continuation).

All arms render the same chat prompt (medium effort, ends with "<think>\n") and sample with the A profile.
  H20  think up to 20480 tokens; if still thinking, splice "Now produce the complete answer." + "</think>"
       immediately (today's server behaviour: mid-word).
  H24  same with 24576 (compute-matched control for S20).
  S20  think up to 20480; if still thinking, (1) let the current line finish (<=256 tokens, stop at newline),
       (2) inject a nudge line, (3) allow up to 4096 more thinking tokens, (4) if still open, finish the line
       (<=256) and force the same closure as H arms.
After the closure every arm generates the answer (<=4096 tokens). The server's own budget sampler is not
active on /completion (it needs reasoning_budget_start_tag, which only the chat endpoint injects).
"""
import argparse
import json
import os
import re
import time

import puzzles
from run import post

CLOSE = "Now produce the complete answer."
NUDGE = "\n\n(Thinking budget reached: finish the current step, check it, then conclude.)\n"
SAMPLING = dict(temperature=1.0, top_k=20, top_p=0.95, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
                cache_prompt=True, return_tokens=True)


def tok(text):
    return post("/tokenize", {"content": text, "add_special": False, "parse_special": True}, 60)["tokens"]


def gen(tokens, n, seed, stop):
    r = post("/completion", dict(SAMPLING, prompt=tokens, n_predict=n, seed=seed, stop=stop), 3600)
    return r.get("tokens") or [], r.get("content", ""), r.get("stop_type"), r.get("stopping_word", "")


def attempt(kind, seed, arm, out_dir):
    q, truth = puzzles.make(kind, seed)
    prompt = post("/apply-template", {"messages": [{"role": "user", "content": q}],
                                      "chat_template_kwargs": {"reasoning_effort": "medium"}}, 60)["prompt"]
    assert prompt.endswith("<think>\n"), prompt[-40:]
    toks = tok(prompt)
    s = seed * 7 + 11
    think_text, events, t0 = "", [], time.time()
    budget = {"H20": 20480, "H24": 24576, "S20": 20480, "Hdbg": 300, "Sdbg": 300}[arm]
    new, txt, st, sw = gen(toks, budget, s, ["</think>"])
    toks += new; think_text += txt
    closed = st == "word"
    events.append(("think", len(new), st))
    if not closed and arm.startswith("S"):
        new, txt, st, _ = gen(toks, 256, s + 1, ["\n"])          # finish the current line
        toks += new; think_text += txt; events.append(("finish_line", len(new), st))
        toks += tok(NUDGE); think_text += NUDGE
        new, txt, st, _ = gen(toks, 4096, s + 2, ["</think>"])   # grace
        toks += new; think_text += txt; events.append(("grace", len(new), st))
        closed = st == "word"
        if not closed:
            new, txt, st, _ = gen(toks, 256, s + 3, ["\n"])
            toks += new; think_text += txt; events.append(("finish_line2", len(new), st))
    forced = not closed
    if forced:
        toks += tok(CLOSE + "</think>\n\n")
    else:
        toks += tok("</think>\n\n")    # the stop string was consumed; re-append the end tag
    new, answer, st, _ = gen(toks, 4096, s + 9, ["<|im_end|>"])
    events.append(("answer", len(new), st))
    found = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", answer)
    ans = int(found[-1].replace(",", "")) if found else None
    think_tokens = sum(n for e, n, _ in events if e != "answer")
    rec = dict(kind=kind, seed=seed, arm=arm, truth=truth, answer=ans, correct=ans == truth, forced=forced,
               think_tokens=think_tokens, total_tokens=think_tokens + events[-1][1], events=events,
               wall_s=round(time.time() - t0, 1), think_tail=think_text[-600:], answer_text=answer[-800:])
    os.makedirs(out_dir, exist_ok=True)
    json.dump(dict(rec, think_text=think_text), open(os.path.join(out_dir, f"{kind}-{seed}-{arm}.json"), "w",
                                                   encoding="utf-8"), ensure_ascii=False)
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    for k, s, arm in json.load(open(a.plan))["order"]:
        if os.path.exists(os.path.join(a.out, f"{k}-{s}-{arm}.json")):
            continue
        r = attempt(k, s, arm, a.out)
        print(json.dumps({x: r[x] for x in ("kind", "seed", "arm", "truth", "answer", "correct", "forced",
                                            "think_tokens", "total_tokens", "wall_s")}), flush=True)
