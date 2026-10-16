"""Exact-copy edit probe (tester A's PatchEval finding: the 9B's `edit` calls fail 34% of the time because oldText is
not an exact copy of the file). Does a 4-bit model of the same size do the same?

Each item: the conversation already holds a `read` tool call and its result (a ~200-line window of a real CPython
stdlib file). The user asks for one small edit inside a named function. The model must answer with an `edit` call
whose oldText is copied exactly from the window and occurs there once (Pi's edit tool rejects anything else).

Sampler as in tester A's runs: temperature 1.0, top-p 0.95, top-k 20, presence 0, thinking on with a 4096-token
per-request budget. Three fixed seeds per item (120 edits per model).

  python bench/exact_copy_probe.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --out results/<model>/exact_copy
"""
import argparse, ast, json, os, sys, time, urllib.request

LIB = os.path.join(os.path.dirname(os.__file__))
FILES = ["textwrap.py", "shlex.py", "argparse.py", "json/decoder.py", "configparser.py", "csv.py", "difflib.py",
         "fnmatch.py", "ipaddress.py", "tokenize.py"]
PER_FILE, WINDOW = 4, 200
TOOLS = [
    {"type": "function", "function": {"name": "read", "description": "Read a file. Returns its text.",
     "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "edit", "description":
     "Replace text in a file. oldText must match the file exactly (every character and space) and must occur only once.",
     "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "oldText": {"type": "string"},
                    "newText": {"type": "string"}}, "required": ["path", "oldText", "newText"]}}},
]
SYSTEM = "You are a coding agent. You change files only with the edit tool."


def items():
    out = []
    for rel in FILES:
        src = open(os.path.join(LIB, rel), encoding="utf-8").read()
        lines = src.splitlines(keepends=True)
        fns = [n for n in ast.walk(ast.parse(src)) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
               and 6 <= (n.end_lineno - n.lineno) <= 40 and len(n.body) >= 2]
        fns.sort(key=lambda n: n.lineno)
        step = max(1, len(fns) // PER_FILE)
        for n in fns[::step][:PER_FILE]:
            mid = (n.lineno + n.end_lineno) // 2
            a = max(1, mid - WINDOW // 2)
            b = min(len(lines), a + WINDOW - 1)
            window = "".join(lines[a - 1:b])
            # the target: the first statement after the docstring (or the first statement), a line the user names by
            # its position only, so the model must copy it from the window
            body = n.body[1:] if isinstance(n.body[0], ast.Expr) and isinstance(getattr(n.body[0], "value", None), ast.Constant) and isinstance(n.body[0].value.value, str) else n.body
            tgt = body[0].lineno
            out.append({"id": f"{rel}:{n.name}:{n.lineno}", "path": rel, "window": window, "a": a, "b": b,
                        "fn": n.name, "fn_line": n.lineno, "target_line": tgt, "target_text": lines[tgt - 1]})
    return out


def ask(base, key, it, seed, budget, presence=0.0, think_only=False):
    user = (f"In `{it['path']}`, in the function `{it['fn']}` (it starts at line {it['fn_line']}), insert the comment "
            f"line `# audited` directly above the first statement of its body after the docstring (line "
            f"{it['target_line']}), with the same indentation as that statement. Make the change with one edit call. "
            f"oldText must be copied exactly from the file and must occur only once in the file.")
    msgs = [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": user},
            {"role": "assistant", "content": "", "tool_calls": [{"id": "call_read_1", "type": "function", "function":
             {"name": "read", "arguments": json.dumps({"path": it["path"]})}}]},
            {"role": "tool", "tool_call_id": "call_read_1", "name": "read",
             "content": f"(lines {it['a']}-{it['b']} of {it['path']})\n" + it["window"]}]
    body = {"messages": msgs, "tools": TOOLS, "tool_choice": "auto", "temperature": 1.0, "top_p": 0.95, "top_k": 20,
            "presence_penalty": presence, "seed": seed, "max_tokens": budget + 4096, "reasoning_budget_tokens": budget,
            "chat_template_kwargs": {"enable_thinking": True}}
    if think_only:
        body["presence_thinking_only"] = True   # engine switch: presence only inside the thinking
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
    return r, time.time() - t0


def score(it, r):
    ch = r["choices"][0]
    calls = [c for c in (ch["message"].get("tool_calls") or []) if c["function"]["name"] == "edit"]
    if not calls:
        return {"verdict": "no_edit_call", "finish": ch.get("finish_reason")}
    try:
        args = json.loads(calls[0]["function"]["arguments"])
    except Exception:
        return {"verdict": "bad_arguments"}
    old, new = args.get("oldText") or "", args.get("newText") or ""
    s = judge(it, old, new)
    s.update(old=old, new=new)   # kept so that serve-side repairs can be scored offline on the same calls
    return s


def judge(it, old, new):
    w = it["window"]
    n = w.count(old) if old else 0
    if n == 1:
        res = w.replace(old, new)
        tl = it["target_text"]
        ind = tl[: len(tl) - len(tl.lstrip())]
        ok = (ind + "# audited\n" + tl) in res
        # lenient: "# audited" (any indentation) is the nearest non-blank line above the target line
        rl, target, loose = res.splitlines(), tl.rstrip("\n"), False
        for j, line in enumerate(rl):
            if line == target:
                k = j - 1
                while k >= 0 and not rl[k].strip():
                    k -= 1
                loose = loose or (k >= 0 and rl[k].strip() == "# audited")
        return {"verdict": "exact_unique", "applied_correct": ok, "applied_loose": loose, "old_len": len(old)}
    if n > 1:
        return {"verdict": "exact_not_unique", "old_len": len(old)}
    norm = lambda s: "\n".join(x.rstrip() for x in s.replace("\t", "    ").splitlines())
    if old and norm(old) in norm(w):
        return {"verdict": "whitespace_mismatch", "old_len": len(old)}
    return {"verdict": "content_mismatch", "old_len": len(old), "old_head": old[:160]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--budget", type=int, default=4096)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--presence", type=float, default=0.0)
    ap.add_argument("--presence-think-only", action="store_true", help="presence penalty only inside the thinking (engine with --presence-thinking-only support)")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    os.makedirs(a.out, exist_ok=True)
    its = items()
    if a.limit:
        its = its[: a.limit]
    path = os.path.join(a.out, "results.jsonl")
    done = {json.loads(l)["id"] for l in open(path, encoding="utf-8")} if os.path.exists(path) else set()
    jobs = [(i, it, sd) for sd in range(a.seeds) for i, it in enumerate(its)]
    with open(path, "a", encoding="utf-8") as f:
        for n_job, (i, it0, sd) in enumerate(jobs):
            it = dict(it0, id=f"{it0['id']}#s{sd}")
            if it["id"] in done:
                continue
            try:
                r, dt = ask(a.base, key, it, 1000 + 100 * sd + i, a.budget, a.presence, a.presence_think_only)
                s = score(it, r)
                t = r.get("timings") or {}
                s.update(seconds=round(dt, 1), completion_tokens=(r.get("usage") or {}).get("completion_tokens"),
                         budget_exhausted=t.get("reasoning_budget_exhausted"))
            except Exception as e:
                s = {"verdict": "error", "error": str(e)[:200]}
            s["id"] = it["id"]
            f.write(json.dumps(s) + "\n"); f.flush()
            print(f"{n_job + 1:3}/{len(jobs)} {it['id']:<44} {s['verdict']}", flush=True)
    rows = [json.loads(l) for l in open(path, encoding="utf-8")]
    from collections import Counter
    c = Counter(r["verdict"] for r in rows)
    calls = sum(v for k, v in c.items() if k not in ("no_edit_call", "error"))
    fails = c["whitespace_mismatch"] + c["content_mismatch"] + c["exact_not_unique"]
    correct = sum(1 for r in rows if r.get("applied_correct"))
    loose = sum(1 for r in rows if r.get("applied_loose"))
    print(f"n={len(rows)} edit calls={calls} exact+unique={c['exact_unique']} (applied exactly as asked {correct}, comment in place {loose}) "
          f"rejected={fails} [content {c['content_mismatch']}, whitespace {c['whitespace_mismatch']}, not unique "
          f"{c['exact_not_unique']}] rejected/calls={100 * fails / max(1, calls):.0f}% no call={c['no_edit_call']} "
          f"errors={c['error']}")


if __name__ == "__main__":
    main()
