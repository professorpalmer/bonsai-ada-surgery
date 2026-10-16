"""Dose ladder (plan G1, DECISIONS 2026-10-07): after a HumanEval failure, which smallest hint makes the model recover,
and can a server make that hint?

For each failed problem of a finished HumanEval arm (results/<size>/humaneval_<arm>_medium), the conversation is
continued from the model's own failed answer with one more user message. Four arms:
  R0  "Your solution is not correct. Try again."                                  (control: no information)
  R1  R0 + "Check it against the examples in the docstring."                      (instruction, no information)
  R2  R0 + the results of the docstring examples, run on the failed code          (information a server can make)
  R3  R0 + the first hidden test that fails, with the actual and expected values (information only a grader has)
Greedy (temperature 0), thinking on at medium, as in the original arm. Recovery = the new answer passes the hidden
tests. Failures with no answer (the thinking ran to the cap) are counted and skipped: no answer to continue from.

  python bench/dose_ladder.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt \
      --arm-dir results/9B/humaneval_serve_medium --out results/9B/dose_ladder [--max-fail 30]
"""
import argparse, json, os, subprocess, sys, tempfile, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import humaneval_run as he  # noqa: E402

PREFIX = ("Complete this Python function so it passes its docstring examples. "
          "Reply with one python code block containing only the function. Do not write tests.\n\n")
BASE_MSG = "Your solution is not correct. Try again."

# Runs in a subprocess (timeout protects against loops in the model's code). Reads JSON on stdin, prints JSON.
CHECKER = r'''
import ast, doctest, io, json, sys
job = json.load(sys.stdin)
ns = {}
try:
    exec(job["code"], ns)
except Exception as e:
    print(json.dumps({"error": f"the code does not run: {type(e).__name__}: {e}"})); sys.exit()
if job["mode"] == "doctest":
    # the prompt ends inside the function: the closing quotes of the docstring would join the last expected output
    text = "\n".join(l for l in job["prompt"].splitlines() if l.strip() not in ('"' * 3, "'" * 3))
    ex = doctest.DocTestParser().get_examples(text)
    if not ex:
        print(json.dumps({"n": 0})); sys.exit()
    test = doctest.DocTest(ex, ns, "docstring", None, 0, None)
    out = io.StringIO()
    runner = doctest.DocTestRunner(optionflags=doctest.NORMALIZE_WHITESPACE)
    runner.run(test, out=out.write)
    keep = [l for l in out.getvalue().splitlines() if not l.strip().startswith(("File ", "Traceback", "exec(", "^", "~", "*****"))
            and "doctest.py" not in l]
    print(json.dumps({"n": len(ex), "failed": runner.failures, "report": "\n".join(keep)[:3000]}))
else:
    cand = ns.get(job["entry"])
    tree = ast.parse(job["test"])
    chk = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "check"), None)
    g = dict(ns); g["candidate"] = cand
    for n in tree.body:                      # module-level helpers and constants of the test file
        if n is not chk and not isinstance(n, (ast.Import, ast.ImportFrom)):
            try: exec(compile(ast.Module([n], []), "test", "exec"), g)
            except Exception: pass
        elif isinstance(n, (ast.Import, ast.ImportFrom)):
            exec(compile(ast.Module([n], []), "test", "exec"), g)
    for st in chk.body:
        src = ast.get_source_segment(job["test"], st) or ""
        try:
            exec(compile(ast.Module([st], []), "test", "exec"), g)
        except AssertionError:
            detail = ""
            t = st.test if isinstance(st, ast.Assert) else None
            if isinstance(t, ast.Compare) and len(t.comparators) == 1:
                try:
                    left = eval(compile(ast.Expression(t.left), "t", "eval"), g)
                    right = eval(compile(ast.Expression(t.comparators[0]), "t", "eval"), g)
                    detail = f"\nYour function returned {left!r}; the test expects {right!r}."
                except Exception:
                    pass
            print(json.dumps({"failed_stmt": src[:600], "detail": detail})); sys.exit()
        except Exception as e:
            print(json.dumps({"failed_stmt": src[:600], "detail": f"\nIt raised {type(e).__name__}: {e}"[:400]})); sys.exit()
    print(json.dumps({"failed_stmt": None}))
'''


def check(job, timeout=20):
    try:
        p = subprocess.run([sys.executable, "-c", CHECKER], input=json.dumps(job), capture_output=True, text=True,
                           timeout=timeout)
        return json.loads(p.stdout.strip().splitlines()[-1])
    except subprocess.TimeoutExpired:
        return {"error": "the code did not finish in 20 seconds (probably an endless loop)"}
    except Exception as e:
        return {"error": f"checker: {e}"}


def hints(problem, code):
    """The four follow-up messages for one failed answer, and what the server-side checks found."""
    info = {}
    r1 = BASE_MSG + " Check it against the examples in the docstring, and fix it."
    d = check({"mode": "doctest", "code": code, "prompt": problem["prompt"]})
    info["doctest"] = {k: d.get(k) for k in ("n", "failed", "error")}
    if d.get("error"):
        r2 = BASE_MSG + f" The server ran your code: {d['error']}."
    elif not d.get("n"):
        r2 = BASE_MSG + " The docstring has no runnable examples to check."
    elif d.get("failed"):
        r2 = BASE_MSG + " The server ran the docstring examples on your code:\n\n" + d["report"]
    else:
        r2 = BASE_MSG + f" The server ran the {d['n']} docstring examples on your code, and all of them pass. Other inputs fail."
    h = check({"mode": "hidden", "code": code, "entry": problem["entry_point"], "test": problem["test"]})
    info["hidden"] = {k: h.get(k) for k in ("failed_stmt", "error")}
    if h.get("error"):
        r3 = BASE_MSG + f" A hidden test failed: {h['error']}."
    elif h.get("failed_stmt"):
        r3 = BASE_MSG + " This hidden test fails:\n\n" + h["failed_stmt"] + h.get("detail", "")
    else:
        r3 = BASE_MSG + " The hidden tests fail when they run as one program."
    return {"R0": BASE_MSG, "R1": r1, "R2": r2, "R3": r3}, info


def ask(base, key, prompt, failed_content, follow, max_tokens):
    body = {"model": "bonsai-2-small", "max_tokens": max_tokens, "temperature": 0, "top_p": 1,
            "chat_template_kwargs": {"enable_thinking": True, "reasoning_effort": "medium"},
            "messages": [{"role": "user", "content": PREFIX + prompt},
                         {"role": "assistant", "content": failed_content},
                         {"role": "user", "content": follow}]}
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    out = json.loads(urllib.request.urlopen(req, timeout=3600).read())
    ch = out["choices"][0]
    return {"content": ch["message"].get("content") or "", "finish": ch.get("finish_reason"),
            "tokens": (out.get("usage") or {}).get("completion_tokens"), "seconds": round(time.time() - t0, 1)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--arm-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-fail", type=int, default=30)
    ap.add_argument("--max-tokens", type=int, default=24576)
    ap.add_argument("--problems", default=os.path.join(os.environ.get("TEMP", "."), "human-eval", "data", "HumanEval.jsonl.gz"))
    ap.add_argument("--timeout", type=float, default=20.0)
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    problems = {p["task_id"]: p for p in he.read_problems(a.problems)}
    rows = json.load(open(os.path.join(a.arm_dir, "summary.json"), encoding="utf-8"))["rows"]
    samples = {json.loads(l)["task_id"]: json.loads(l) for l in open(os.path.join(a.arm_dir, "samples.jsonl"), encoding="utf-8")}
    failed = [r for r in rows if not r["passed"]]
    no_answer = [r for r in failed if not (samples[r["task_id"]].get("content") or "").strip()]
    todo = [r for r in failed if (samples[r["task_id"]].get("content") or "").strip()][: a.max_fail]
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "results.jsonl")
    done = {(json.loads(l)["task_id"], json.loads(l)["arm"]) for l in open(path, encoding="utf-8")} if os.path.exists(path) else set()
    print(f"failed {len(failed)}; no answer (cap) {len(no_answer)}; continued {len(todo)}", flush=True)
    with open(path, "a", encoding="utf-8") as f:
        for i, r in enumerate(todo):
            p, s = problems[r["task_id"]], samples[r["task_id"]]
            msgs, info = hints(p, s.get("code") or "")
            for arm in ("R0", "R1", "R2", "R3"):
                if (r["task_id"], arm) in done:
                    continue
                try:
                    g = ask(a.base, key, p["prompt"], s["content"], msgs[arm], a.max_tokens)
                    code = he.extract_code(g["content"], p["entry_point"])
                    res = he.run_program(he.build_program(p, code), a.timeout) if code else "failed: empty"
                except Exception as e:
                    g, res = {"error": str(e)[:200]}, "error"
                rec = {"task_id": r["task_id"], "arm": arm, "recovered": res == "passed", "result": res[:200],
                       "finish": g.get("finish"), "tokens": g.get("tokens"), "seconds": g.get("seconds"),
                       "server_checks": info, "hint": msgs[arm][:1500]}
                f.write(json.dumps(rec) + "\n"); f.flush()
                print(f"{i + 1:2}/{len(todo)} {r['task_id']:<14} {arm} {'RECOVERED' if rec['recovered'] else 'no'}", flush=True)
    recs = [json.loads(l) for l in open(path, encoding="utf-8")]
    n = len({x["task_id"] for x in recs})
    line = "  ".join(f"{arm} {sum(x['recovered'] for x in recs if x['arm'] == arm)}/{n}" for arm in ("R0", "R1", "R2", "R3"))
    print(f"recovered: {line}   (failed {len(failed)}, no answer {len(no_answer)}, continued {n})")


if __name__ == "__main__":
    main()
