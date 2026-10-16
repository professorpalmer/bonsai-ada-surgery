"""Long-exact-work suite: the small set of tasks on which Bonsai 2 27B's gap to its teacher shows up, packaged so
that one command measures any OpenAI-compatible endpoint and, optionally, pairs two endpoints request by request.

    python suite/run_suite.py --base http://127.0.0.1:18080 --key-file artifacts/api_key.txt --out suite-out
    python suite/run_suite.py --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 ... (paired: A vs B)

Families (all graders deterministic; model code runs only inside the WASI sandbox from layer/):
  coding       three contracts (tar+gzip, ZIP, MIME): write solution.py with write_file / run_python, 12 responses,
               graded by output properties on hidden requests (cases.py)
  computation  single chat requests with brute-force integer truths: knapsack, digits, lcs (bookkeeping) and
               sales, weblog (data in the prompt) (puzzles.py)
  workspace    tool-using data tasks graded on the final state, incl. byte-exact copy (envs.py)
Sampling and reasoning controls are sent per request (temperature 1.0, top-p 0.95, top-k 20, min-p 0.05, medium
effort, reasoning budget 20480 where the server supports it). Seeds are fixed; the default plan is the frozen one.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "layer", "wasi-python"))
import cases  # noqa: E402
import envs  # noqa: E402
import puzzles  # noqa: E402
import sandbox  # noqa: E402

PROFILE = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
               reasoning_format="deepseek", reasoning_effort="medium", chat_template_kwargs={"reasoning_effort": "medium"},
               reasoning_budget_tokens=20480, stream=False, cache_prompt=True)
DEFAULT_PLAN = {
    "coding": [(c, s) for c in ("suite-tar-01", "xfer-zip-01", "xfer-mime-01") for s in (1, 2, 3, 4)],
    "computation": [(k, s) for k in ("knapsack", "digits", "lcs", "sales", "weblog") for s in (1, 2, 3)],
    "workspace": [(k, s) for k in ("invoiceH", "dedupeH", "ledgerH", "chain", "copy") for s in (1, 2)],
}
MAX_FILES, MAX_BYTES = 16, 128 * 1024
WS_SYSTEM = ("You are an operations agent working in a data workspace. Use the tools to inspect the data and make "
             "the requested changes. When you are finished, call submit_answer exactly once.")
WS_REMINDER = "Continue the task using the tools. When you are finished, call submit_answer."


class Client:
    def __init__(self, base, key, model):
        self.base, self.key, self.model = base.rstrip("/"), key, model

    def chat(self, body, timeout=3600):
        body = dict(body, model=self.model)
        req = urllib.request.Request(self.base + "/v1/chat/completions", data=json.dumps(body).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {self.key}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))


# ---------------------------------------------------------------- coding
def run_coding(client, case_id, seed, max_responses=12):
    system, user, tools = cases.prompts(case_id)
    msgs = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    ws, log, t0, tokens, n, terminal = {}, [], time.time(), 0, 0, "response_cap"
    while n < max_responses:
        body = dict(PROFILE, messages=msgs, tools=tools, tool_choice="auto", max_tokens=49152, seed=seed * 7919 + n)
        try:
            r = client.chat(body)
        except Exception as e:
            terminal = "infra_error"
            log.append({"infra_error": repr(e)[:300]})
            break
        n += 1
        m = r["choices"][0]["message"]
        tokens += (r.get("usage") or {}).get("completion_tokens", 0)
        log.append({"step": n, "reasoning": m.get("reasoning_content") or "", "content": m.get("content"), "tool_calls": m.get("tool_calls")})
        am = {"role": "assistant", "content": m.get("content") or ""}
        calls = m.get("tool_calls") or []
        if calls:
            am["tool_calls"] = calls
        msgs.append(am)
        if not calls:
            terminal = "natural_stop"
            break
        for c in calls:
            try:
                a = json.loads(c["function"]["arguments"])
            except Exception:
                a = None
            name = c["function"]["name"]
            if a is None:
                out = {"ok": False, "error": "invalid_arguments"}
            elif name == "write_file":
                path, text = a.get("path", ""), a.get("text", "")
                data = text.encode("utf-8")
                if (not path or "/" in path or "\\" in path or ".." in path or len(data) > MAX_BYTES
                        or (path not in ws and len(ws) >= MAX_FILES)):
                    out = {"ok": False, "error": "invalid_path_or_size"}
                else:
                    ws[path] = data
                    out = {"ok": True, "bytes": len(data)}
            elif name == "run_python":
                path = a.get("path", "")
                if path not in ws or not path.endswith(".py"):
                    out = {"ok": False, "failure": "invalid_path"}
                else:
                    res = sandbox.run(dict(ws), ["/work/" + path], stdin=(a.get("stdin") or "").encode("utf-8"), timeout=8.0, mem_mb=128)
                    out = {"ok": True, "outcome": "timeout" if res["timed_out"] else "completed", "exit_code": res["exit_code"],
                           "stdout": res["stdout"][:16000].decode("utf-8", "replace"), "stderr": res["stderr"][-6000:].decode("utf-8", "replace")}
            else:
                out = {"ok": False, "error": "unknown_tool"}
            log.append({"tool": name, "result": {k: (v[:400] if isinstance(v, str) else v) for k, v in out.items()}})
            msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": name, "content": json.dumps(out, ensure_ascii=False, separators=(",", ":"))})
    g = cases.grade(case_id, ws, normal_completion=(terminal == "natural_stop"))
    return dict(ok=g.get("functional_result_correct") is True, detail=g.get("reasons"), tokens=tokens, responses=n,
                terminal=terminal, wall_s=round(time.time() - t0, 1),
                trace=dict(log=log, workspace={k: v.decode("utf-8", "replace") for k, v in ws.items()}, grade=g))


# ---------------------------------------------------------------- computation
def parse_answer(text):
    f = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", text or "")
    return int(f[-1].replace(",", "")) if f else None


def run_computation(client, kind, seed):
    q, truth = puzzles.make(kind, seed)
    t0 = time.time()
    body = dict(PROFILE, messages=[{"role": "user", "content": q}], max_tokens=49152, seed=seed * 7 + 11)
    try:
        r = client.chat(body)
    except Exception as e:
        return dict(ok=False, detail="infra_error: " + repr(e)[:200], tokens=None, wall_s=round(time.time() - t0, 1), trace=None)
    m = r["choices"][0]["message"]
    ans = parse_answer(m.get("content"))
    return dict(ok=ans == truth, detail=f"answer {ans} truth {truth}", tokens=(r.get("usage") or {}).get("completion_tokens"),
                runs=len(r.get("interpreter_trace") or []), wall_s=round(time.time() - t0, 1), trace=r)


# ---------------------------------------------------------------- workspace
def run_workspace(client, kind, seed, max_responses=20, wall=1500):
    env = envs.make(kind, seed)
    msgs = [{"role": "system", "content": WS_SYSTEM}, {"role": "user", "content": env.task}]
    t0, tokens, n, reminders, status, log = time.time(), 0, 0, 0, "cap_responses", []
    while n < max_responses and time.time() - t0 < wall:
        body = dict(PROFILE, messages=msgs, tools=envs.TOOLS, tool_choice="auto", max_tokens=32768, seed=(seed * 1000 + n) % 2**31)
        try:
            r = client.chat(body, timeout=900)
        except Exception as e:
            status = "infra_error"
            log.append({"infra_error": repr(e)[:300]})
            break
        n += 1
        m = r["choices"][0]["message"]
        tokens += (r.get("usage") or {}).get("completion_tokens", 0)
        log.append({"step": n, "reasoning": m.get("reasoning_content") or "", "content": m.get("content"), "tool_calls": m.get("tool_calls")})
        am = {"role": "assistant", "content": m.get("content") or ""}
        calls = m.get("tool_calls") or []
        if calls:
            am["tool_calls"] = calls
        msgs.append(am)
        if not calls:
            if reminders >= 1:
                status = "no_submit"
                break
            reminders += 1
            msgs.append({"role": "user", "content": WS_REMINDER})
            continue
        done = False
        for c in calls:
            fn = c["function"]["name"]
            try:
                args = json.loads(c["function"]["arguments"]) if isinstance(c["function"]["arguments"], str) else c["function"]["arguments"]
                out = env.call(fn, args)
            except json.JSONDecodeError as e:
                out = {"error": f"arguments are not valid JSON: {e}"}
            log.append({"tool": fn, "result": out})
            msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": fn, "content": json.dumps(out, ensure_ascii=False)})
            if fn == "submit_answer" and "error" not in out:
                done = True
        if done:
            status = "submitted"
            break
    g = env.grade()
    return dict(ok=bool(g.get("functional")), detail=f"{status}; full_pass={g.get('full_pass')}", tokens=tokens, responses=n,
                wall_s=round(time.time() - t0, 1), trace=dict(log=log, grade=g))


RUNNERS = {"coding": run_coding, "computation": run_computation, "workspace": run_workspace}


# ---------------------------------------------------------------- driver
def load_plan(path, limit):
    plan = json.load(open(path)) if path else DEFAULT_PLAN
    order = [(fam, name, seed) for fam in ("coding", "computation", "workspace") for name, seed in plan.get(fam, [])]
    if limit:
        seen, out = {}, []
        for item in order:
            if seen.get(item[0], 0) < limit:
                seen[item[0]] = seen.get(item[0], 0) + 1
                out.append(item)
        order = out
    return order


def scoreboard(results, arms):
    fams = {}
    for r in results:
        key = (r["family"], r["name"])
        fams.setdefault(key, {}).setdefault((r["seed"]), {})[r["arm"]] = r
    lines = ["| family | task | " + " | ".join(arms) + (" | rescues / losses (B vs A)" if len(arms) == 2 else "") + " |",
             "| --- | --- | " + " | ".join("---:" for _ in arms) + (" | ---" if len(arms) == 2 else "") + " |"]
    tot = {a: [0, 0] for a in arms}
    tres = tlos = 0
    for (fam, name), seeds in sorted(fams.items()):
        counts = {a: [0, 0] for a in arms}
        res = los = 0
        for seed, by in seeds.items():
            for a in arms:
                if a in by:
                    counts[a][1] += 1
                    counts[a][0] += bool(by[a]["ok"])
            if len(arms) == 2 and all(a in by for a in arms):
                A, B = by[arms[0]]["ok"], by[arms[1]]["ok"]
                res += (B and not A)
                los += (A and not B)
        for a in arms:
            tot[a][0] += counts[a][0]
            tot[a][1] += counts[a][1]
        tres += res
        tlos += los
        row = f"| {fam} | {name} | " + " | ".join(f"{counts[a][0]}/{counts[a][1]}" for a in arms)
        if len(arms) == 2:
            row += f" | {res} / {los}"
        lines.append(row + " |")
    row = "| **total** | | " + " | ".join(f"**{tot[a][0]}/{tot[a][1]}**" for a in arms)
    if len(arms) == 2:
        row += f" | **{tres} / {tlos}**"
    lines.append(row + " |")
    toks = {a: sum((r["tokens"] or 0) for r in results if r["arm"] == a) for a in arms}
    lines.append("")
    lines.append("completion tokens: " + ", ".join(f"{a} {toks[a]:,}" for a in arms))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="OpenAI-compatible server (arm A)")
    ap.add_argument("--base-b", default="", help="optional second server (arm B); every request is sent to both")
    ap.add_argument("--key-file", default=os.path.join(HERE, "..", "artifacts", "api_key.txt"))
    ap.add_argument("--model", default="bonsai-2-27b")
    ap.add_argument("--out", required=True)
    ap.add_argument("--plan", default="", help="JSON {family: [[name, seed], ...]}; default: the frozen plan")
    ap.add_argument("--limit", type=int, default=0, help="first N items per family (smoke test)")
    ap.add_argument("--label-a", default="A")
    ap.add_argument("--label-b", default="B")
    a = ap.parse_args()
    key = open(a.key_file, encoding="utf-8").read().strip() if os.path.exists(a.key_file) else ""
    arms = [(a.label_a, Client(a.base, key, a.model))] + ([(a.label_b, Client(a.base_b, key, a.model))] if a.base_b else [])
    os.makedirs(os.path.join(a.out, "traces"), exist_ok=True)
    res_path = os.path.join(a.out, "results.jsonl")
    done = set()
    results = []
    if os.path.exists(res_path):
        for l in open(res_path, encoding="utf-8"):
            r = json.loads(l)
            results.append(r)
            done.add((r["family"], r["name"], r["seed"], r["arm"]))
    order = load_plan(a.plan, a.limit)
    for i, (fam, name, seed) in enumerate(order):
        for label, client in (arms if i % 2 == 0 else arms[::-1]):   # alternate which arm goes first
            if (fam, name, seed, label) in done:
                continue
            r = RUNNERS[fam](client, name, seed)
            trace = r.pop("trace", None)
            if trace is not None:
                json.dump(trace, open(os.path.join(a.out, "traces", f"{fam}-{name}-{seed}-{label}.json"), "w", encoding="utf-8"), ensure_ascii=False)
            rec = dict(family=fam, name=name, seed=seed, arm=label, **r)
            results.append(rec)
            with open(res_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            print(json.dumps({k: rec.get(k) for k in ("family", "name", "seed", "arm", "ok", "tokens", "wall_s", "detail")}, ensure_ascii=False)[:220], flush=True)
    board = scoreboard(results, [l for l, _ in arms])
    open(os.path.join(a.out, "scoreboard.md"), "w", encoding="utf-8").write(board + "\n")
    print("\n" + board)


if __name__ == "__main__":
    main()
