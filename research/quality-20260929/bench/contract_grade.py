"""Grade a candidate solution.py for a frozen author-contract case: run it in the WASI sandbox on the case's
hidden request (twice for bundles, as the Mac runner did) and apply the original host oracles unchanged."""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVID = os.path.join(HERE, "..", "evidence", "evidence")
CASES_DIR = os.path.join(EVID, "frozen-author-contract-cases-v1")
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tooling", "wasi-python"))
import sandbox  # noqa: E402

_spec = importlib.util.spec_from_file_location("oracles", os.path.join(CASES_DIR, "host", "oracles.py"))
oracles = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(oracles)

DEV = {c["id"]: c for c in json.load(open(os.path.join(CASES_DIR, "fixtures", "development.json"),
                                          encoding="utf-8"))["cases"]}


def json_bytes(v):
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")


def grade(case_id, files, normal_completion=True, timeout=8.0, mem_mb=128):
    """files: {name: bytes} of the candidate workspace (must contain solution.py)."""
    case = DEV[case_id]
    if "solution.py" not in files:
        return {"task_success": False, "functional_result_correct": None, "reasons": ["candidate_unavailable"]}
    fixtures = {}
    import base64
    for name, b64 in (case.get("fixture_files") or {}).items():
        fixtures[name] = base64.b64decode(b64)
    runs = []
    for _ in range(2 if case["family"] == "compressed_bundle" else 1):
        r = sandbox.run(dict(files, **fixtures), ["/work/solution.py"], stdin=json_bytes(case["request"]),
                        timeout=timeout, mem_mb=mem_mb)
        runs.append(r)
    try:
        out = runs[0]["stdout"].decode("utf-8")
    except UnicodeDecodeError:
        out = ""
    rep = None
    if len(runs) == 2:
        try:
            rep = runs[1]["stdout"].decode("utf-8")
        except UnicodeDecodeError:
            rep = ""
    completed = all(r["exit_code"] == 0 and not r["timed_out"] for r in runs)
    g = oracles.grade_case(case, out, repeat_output_text=rep, process_receipt={"violations": []},
                           normal_completion=normal_completion and completed)
    g = dict(g)
    if not completed:
        g["task_success"] = False
    g["exec"] = [{"exit": r["exit_code"], "timed_out": r["timed_out"], "stderr_tail": r["stderr"][-300:].decode("utf-8", "replace")}
                 for r in runs]
    return g


if __name__ == "__main__":
    # validation: regrade Codex's saved A-baseline candidates for the coding cases
    runs = os.path.join(EVID, "spec-ab-v1", "runs-A")
    for d in sorted(os.listdir(runs)):
        cand = os.path.join(runs, d, "candidate")
        if not os.path.isdir(cand) or ("bundle" not in d and "checklist" not in d):
            continue
        case_id = "dev-" + d.split("-dev-")[1].rsplit("-", 1)[0]
        files = {n: open(os.path.join(cand, n), "rb").read() for n in os.listdir(cand)}
        rec = json.load(open(os.path.join(runs, d, "private", "receipt.json"), encoding="utf-8"))
        theirs = rec.get("final_grade") or rec.get("grade") or {}
        mine = grade(case_id, files, normal_completion=theirs.get("normal_completion", True))
        keys = ("functional_result_correct", "protocol_valid", "reasons")
        same = all(mine.get(k) == theirs.get(k) for k in keys)
        print(f"{'MATCH' if same else 'DIFF '} {d:28s} codex={ {k: theirs.get(k) for k in keys} } mine={ {k: mine.get(k) for k in keys} }")
        if not same:
            print("        exec:", mine["exec"])
