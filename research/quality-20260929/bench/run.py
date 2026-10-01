"""Agent-loop runner for the host-simulated tool tasks.

Arms (history policy only; everything else identical):
  P0  assistant turns are sent back as OpenAI clients usually do: content + tool_calls, no reasoning_content
  P1  each assistant turn also carries the reasoning_content the server returned for it
Evidence: one JSONL per attempt, flushed per event (request written before it is sent). No key in any file.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

import envs
import regex_env

ROOT = os.path.dirname(os.path.abspath(__file__))
KEY = open(os.path.join(ROOT, "..", "..", "api_key.txt")).read().strip()
BASE = os.environ.get("BONSAI_BASE", "http://127.0.0.1:8080")
SYSTEM = ("You are an operations agent working in a data workspace. Use the tools to inspect the data and make "
          "the requested changes. When you are finished, call submit_answer exactly once.")
SYSTEM_RX = "You are a careful software engineer. Use the tools to test your work, then submit it."
REMINDER = "Continue the task using the tools. When you are finished, call submit_answer."
PROFILE = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
               reasoning_format="deepseek", reasoning_effort="medium",
               chat_template_kwargs={"reasoning_effort": "medium"}, reasoning_budget_tokens=20480,
               max_tokens=32768, stream=False, cache_prompt=True, tool_choice="auto")


def post(path, body, timeout):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def get(path):
    req = urllib.request.Request(BASE + path, headers={"Authorization": f"Bearer {KEY}"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def run_attempt(kind, seed, arm, out_dir, max_responses=20, wall=1500, req_timeout=900, policy_fn=None):
    if kind.startswith("rx-"):
        env, tools, system = regex_env.RegexEnv(kind[3:], seed), regex_env.TOOLS, SYSTEM_RX
    else:
        env, tools, system = envs.make(kind, seed), envs.TOOLS, SYSTEM
    os.makedirs(out_dir, exist_ok=True)
    name = f"{kind}-{seed}-{arm}"
    log = open(os.path.join(out_dir, name + ".jsonl"), "w", encoding="utf-8")

    def ev(**kw):
        kw["t"] = round(time.time(), 3)
        log.write(json.dumps(kw, ensure_ascii=False) + "\n")
        log.flush()

    msgs = [{"role": "system", "content": system}, {"role": "user", "content": env.task}]
    ev(event="start", kind=kind, seed=seed, arm=arm, task=env.task, profile=PROFILE)
    t0 = time.time()
    usage = {"completion_tokens": 0, "prompt_tokens": 0, "cached": 0, "draft_n": 0, "draft_acc": 0}
    status, n_resp, reminders = "cap_responses", 0, 0
    while n_resp < max_responses:
        if time.time() - t0 > wall:
            status = "cap_wall"
            break
        body = dict(PROFILE, model="bonsai-2-27b", messages=msgs, tools=tools,
                    seed=(seed * 1000 + n_resp) % 2**31)
        raw = json.dumps(body, ensure_ascii=False, sort_keys=True)
        ev(event="request", step=n_resp, sha256=hashlib.sha256(raw.encode()).hexdigest(), body=body)
        try:
            resp = post("/v1/chat/completions", body, req_timeout)
        except Exception as e:     # transport / timeout: infrastructure, not a model outcome
            ev(event="infra_error", step=n_resp, error=repr(e)[:500])
            status = "infra_error"
            break
        n_resp += 1
        ev(event="response", step=n_resp - 1, body=resp)
        ch = resp["choices"][0]
        m = ch["message"]
        u = resp.get("usage") or {}
        tm = resp.get("timings") or {}
        usage["completion_tokens"] += u.get("completion_tokens", 0)
        usage["prompt_tokens"] += u.get("prompt_tokens", 0)
        usage["cached"] += tm.get("cache_n", 0)
        usage["draft_n"] += tm.get("draft_n", 0)
        usage["draft_acc"] += tm.get("draft_n_accepted", 0)
        am = {"role": "assistant", "content": m.get("content") or ""}
        if m.get("tool_calls"):
            am["tool_calls"] = m["tool_calls"]
        if arm == "P1" and m.get("reasoning_content"):
            am["reasoning_content"] = m["reasoning_content"]
        if policy_fn:
            am = policy_fn(am, m)
        msgs.append(am)
        calls = m.get("tool_calls") or []
        if not calls:
            if reminders >= 1:
                status = "no_submit"
                break
            reminders += 1
            msgs.append({"role": "user", "content": REMINDER})
            ev(event="reminder", finish=ch.get("finish_reason"))
            continue
        done = False
        for c in calls:
            fn = c["function"]["name"]
            try:
                args = json.loads(c["function"]["arguments"]) if isinstance(c["function"]["arguments"], str) \
                    else c["function"]["arguments"]
            except json.JSONDecodeError as e:
                args, out = None, {"error": f"arguments are not valid JSON: {e}"}
            if args is not None:
                out = env.call(fn, args)
            ev(event="tool", step=n_resp - 1, name=fn, args=args, result=out)
            msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": fn,
                         "content": json.dumps(out, ensure_ascii=False)})
            if fn in ("submit_answer", "submit_regex") and "error" not in out:
                done = True
        if done:
            status = "submitted"
            break
    g = env.grade()
    g.update(kind=kind, seed=seed, arm=arm, status=status, responses=n_resp, wall_s=round(time.time() - t0, 1),
             **usage)
    ev(event="grade", **g)
    log.close()
    return g


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    plan = json.load(open(a.plan))
    res_path = os.path.join(a.out, "results.jsonl")
    os.makedirs(a.out, exist_ok=True)
    done = set()
    if os.path.exists(res_path):
        for line in open(res_path, encoding="utf-8"):
            r = json.loads(line)
            done.add((r["kind"], r["seed"], r["arm"]))
    for item in plan["order"]:
        k, s, arm = item
        if (k, s, arm) in done:
            continue
        slots = get("/slots")
        g = run_attempt(k, s, arm, os.path.join(a.out, "attempts"), **plan.get("limits", {}))
        with open(res_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(g, ensure_ascii=False) + "\n")
        print(json.dumps({x: g[x] for x in ("kind", "seed", "arm", "full_pass", "functional", "process_ok",
                                             "status", "responses", "wall_s", "completion_tokens")}), flush=True)
