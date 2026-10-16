"""Offline check of layer/example_check.py on recorded HumanEval answers: how often the example check fires on failed
answers (it may help) and on passed answers (it must not, or it would push a right answer to change).
  python bench/example_check_eval.py results/2B/humaneval_serve_medium [more dirs...]
"""
import gzip, json, os, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "layer"))
import example_check as ec  # noqa: E402

PROBLEMS = os.path.join(os.environ.get("TEMP", "."), "human-eval", "data", "HumanEval.jsonl.gz")
probs = {p["task_id"]: p for p in map(json.loads, gzip.open(PROBLEMS, "rt", encoding="utf-8"))}


def run(prog):
    try:
        p = subprocess.run([sys.executable, "-c", prog], capture_output=True, text=True, timeout=10)
        return json.loads(p.stdout.strip().splitlines()[-1])
    except subprocess.TimeoutExpired:
        return {"error": "the code did not finish in 10 seconds"}
    except Exception as e:
        return {"error": f"checker: {e}"}


for d in sys.argv[1:]:
    rows = {r["task_id"]: r for r in json.load(open(os.path.join(d, "summary.json"), encoding="utf-8"))["rows"]}
    c = {"passed": [0, 0], "failed": [0, 0]}
    unchecked = 0
    fp = []
    for s in map(json.loads, open(os.path.join(d, "samples.jsonl"), encoding="utf-8")):
        tid = s["task_id"]
        t = ec.task(probs[tid]["prompt"])
        code = ec.answer_code(s.get("content") or "", t[0]) if t else None
        if not t or not code:
            unchecked += 1
            continue
        fired = ec.follow_up(run(ec.checker_program(code, t[1], t[2]))) is not None
        k = "passed" if rows[tid]["passed"] else "failed"
        c[k][0] += fired
        c[k][1] += 1
        if fired and k == "passed":
            fp.append(tid)
    print(f"{d}: fires on failed answers {c['failed'][0]}/{c['failed'][1]}, on passed answers {c['passed'][0]}/{c['passed'][1]}"
          f" (cannot check {unchecked}){'; passed but fired: ' + ', '.join(fp) if fp else ''}")
