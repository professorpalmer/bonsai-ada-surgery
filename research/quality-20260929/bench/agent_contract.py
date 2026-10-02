"""Agentic coding cases from the frozen author-contract set, on this PC.

Prompts and tool schemas are the exact frozen ones from spec-ab-v1/inputs (what Codex sent). write_file keeps
files in an in-memory workspace (single-component names, <=16 files, <=128 KiB each); run_python executes a
workspace file in the WASI sandbox (8 s, 128 MB, no network/host files), like the Mac's read-only confinement.
Final grading: contract_grade.grade (original oracles, validated 4/4 against Codex's receipts).
History policy as Codex: assistant turns are sent back without reasoning_content.
"""
import argparse
import json
import os
import time

import contract_grade
from run import post

HERE = os.path.dirname(os.path.abspath(__file__))
INPUTS = os.path.join(HERE, "..", "evidence", "evidence", "spec-ab-v1", "inputs")
FROZEN = {"dev-bundle-01": "00-dev-bundle-01-11729", "dev-checklist-01": "06-dev-checklist-01-11729",
          "dev-bundle-02": "00-dev-bundle-01-11729",   # same family prompt (public example), different hidden request
          "dev-batch-01": "02-dev-batch-01-11729", "dev-batch-02": "04-dev-batch-02-11729"}
BUDGET = {"B20": 20480, "B40": 40960, "CK": 20480, "R12": 20480, "R24": 20480, "DOC": 20480, "RAW": 20480, "PROD": 20480, "PRODNL": 20480, "C1": 20480, "C2": 20480, "C2U": 20480, "C2P": 20480}
PREFER = ("Use the library functions listed above instead of implementing these formats or algorithms by hand; "
          "they already implement them correctly.")
BASEURL = {"PROD": "http://127.0.0.1:8081", "PRODNL": "http://127.0.0.1:8081"}   # PRODNL: layer with the API check off   # everything else: llama-server directly
import importlib.util as _ilu
_bs = _ilu.spec_from_file_location("batch_handlers", os.path.join(contract_grade.CASES_DIR, "host", "batch_handlers.py"))
batch_handlers = _ilu.module_from_spec(_bs); _bs.loader.exec_module(batch_handlers)
DOC_NOTES = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "api_notes_tar_gzip.md"), encoding="utf-8").read()
RESPONSES = {"R24": 24}
CHECK_TOOL = {"type": "function", "function": {"name": "check_solution", "description": "Run the workspace solution.py on the disclosed public example (twice, as the grader does) and return the grader's verdict for that public example only: whether it passed and the failure reasons (for example invalid_gzip, invalid_tar, wrong members, not reproducible). Hidden cases are never run.", "parameters": {"type": "object", "properties": {}, "required": []}}}
MAX_FILES, MAX_BYTES = 16, 128 * 1024


def load_case(case_id):
    d = os.path.join(INPUTS, FROZEN[case_id])
    p = json.load(open(os.path.join(d, "prompts.json"), encoding="utf-8"))
    s = json.load(open(os.path.join(d, "schemas.json"), encoding="utf-8"))
    return p["system"], p["user"], s


def public_case(user):
    tag = "Disclosed public inputs:" + chr(10)
    i = user.index(tag) + len(tag)
    j = user.index(chr(10), i)
    return json.loads(user[i:j])["public_example"]


def check_solution(ws, pub):
    import sandbox
    if "solution.py" not in ws:
        return {"ok": False, "error": "solution.py not written yet"}
    runs = [sandbox.run(dict(ws), ["/work/solution.py"], stdin=contract_grade.json_bytes(pub["request"]),
                        timeout=8.0, mem_mb=128) for _ in range(2 if pub["family"] == "compressed_bundle" else 1)]
    texts = [r["stdout"].decode("utf-8", "replace") for r in runs]
    g = contract_grade.oracles.grade_case(pub, texts[0], repeat_output_text=texts[1] if len(texts) > 1 else None,
                                          process_receipt={"violations": []}, normal_completion=True)
    ok = bool(g.get("functional_result_correct")) and bool(g.get("protocol_valid"))
    return {"ok": True, "public_example_passed": ok, "reasons": g.get("reasons"),
            "exit_codes": [r["exit_code"] for r in runs],
            "stderr_tail": runs[0]["stderr"][-1500:].decode("utf-8", "replace")}


def attempt(case_id, seed, arm, out_dir, max_responses=12):
    system, user, tools = load_case(case_id)
    pub = public_case(user)
    if arm in ("C2U", "C2P"):   # v2 cards at the END of the user message (where the hand notes sit); C2P adds one generic sentence
        import sys as _sys
        _t = os.path.join(HERE, "..", "..", "..", "tooling")
        if _t not in _sys.path:
            _sys.path.insert(0, _t)
        import apicards_v2
        _cards = apicards_v2.cards_for_request({"messages": [{"role": "system", "content": system}, {"role": "user", "content": user}], "tools": tools})
        user = user + chr(10) + chr(10) + _cards + ((chr(10) + chr(10) + PREFER) if arm == "C2P" else "")
    if arm in ("C1", "C2"):   # auto-generated API cards appended to the system message, exactly as the layer does
        import sys as _sys
        _t = os.path.join(HERE, "..", "..", "..", "tooling")
        if _t not in _sys.path:
            _sys.path.insert(0, _t)
        import apicards, apicards_v2
        _mod = apicards if arm == "C1" else apicards_v2
        _cards = _mod.cards_for_request({"messages": [{"role": "system", "content": system}, {"role": "user", "content": user}], "tools": tools})
        system = system + chr(10) + chr(10) + _cards
    if arm == "DOC":   # the only change: verified stdlib API notes appended to the user message
        user = user + chr(10) + chr(10) + DOC_NOTES
    if arm in RESPONSES:   # the only change: the response allowance, stated where the frozen prompt states it
        n_new = RESPONSES[arm]
        assert "At most 12 model responses" in user and "exactly 12 MODEL RESPONSES" in user
        user = user.replace("At most 12 model responses", f"At most {n_new} model responses").replace(
            "exactly 12 MODEL RESPONSES", f"exactly {n_new} MODEL RESPONSES")
        max_responses = n_new
    if arm == "CK":
        tools = tools + [CHECK_TOOL]
    msgs = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    ws, log, t0 = {}, [], time.time()
    import run as _run
    _run.BASE = BASEURL.get(arm, "http://127.0.0.1:8080")
    batch_events, final_text = [], ""
    usage = {"completion": 0, "prompt": 0}
    terminal, n = "response_cap", 0
    while n < max_responses:
        body = dict(model="bonsai-2-27b", messages=msgs, tools=tools, tool_choice="auto", temperature=1.0,
                    top_p=0.95, top_k=20, min_p=0.05, repeat_penalty=1.0, presence_penalty=0.0,
                    reasoning_format="deepseek", reasoning_effort="medium",
                    chat_template_kwargs={"reasoning_effort": "medium"}, reasoning_budget_tokens=BUDGET[arm],
                    max_tokens=49152, stream=False, cache_prompt=True, seed=seed + n)
        if arm == "PRODNL":
            body["api_lint"] = False
        try:
            r = post("/v1/chat/completions", body, 7200)
        except Exception as e:
            terminal = "infra_error"
            log.append({"infra_error": repr(e)[:300]})
            break
        n += 1
        m = r["choices"][0]["message"]
        usage["completion"] += r["usage"]["completion_tokens"]
        usage["prompt"] += r["usage"]["prompt_tokens"]
        rc = m.get("reasoning_content") or ""
        log.append({"step": n, "finish": r["choices"][0].get("finish_reason"), "reasoning_chars": len(rc),
                    "forced": "Now produce the complete answer" in rc, "content": m.get("content"),
                    "tool_calls": m.get("tool_calls"), "usage": r["usage"]})
        am = {"role": "assistant", "content": m.get("content") or ""}
        calls = m.get("tool_calls") or []
        if calls:
            am["tool_calls"] = calls
        msgs.append(am)
        if not calls:
            terminal = "natural_stop"
            final_text = m.get("content") or ""
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
            elif name == "batch_work":
                jobs = a.get("jobs")
                try:
                    out = {"ok": True, "results": batch_handlers.batch_work(jobs)}
                    batch_events.append({"tool": "batch_work", "jobs": jobs, "settled": True})
                except Exception:
                    out = {"ok": False, "error": "invalid_jobs"}
                    batch_events.append({"tool": "batch_work", "jobs": None, "settled": False})
            elif name == "check_solution" and arm == "CK":
                out = check_solution(ws, pub)
            elif name == "run_python":
                path = a.get("path", "")
                if path not in ws or not path.endswith(".py"):
                    out = {"ok": False, "failure": "invalid_path"}
                else:
                    import sandbox
                    res = sandbox.run(dict(ws), ["/work/" + path], stdin=(a.get("stdin") or "").encode("utf-8"),
                                      timeout=8.0, mem_mb=128)
                    out = {"ok": True, "outcome": "timeout" if res["timed_out"] else "completed",
                           "exit_code": res["exit_code"], "stdout": res["stdout"][:16000].decode("utf-8", "replace"),
                           "stderr": res["stderr"][-6000:].decode("utf-8", "replace")}
            else:
                out = {"ok": False, "error": "unknown_tool"}
            log.append({"tool": name, "result": {k: (v[:400] if isinstance(v, str) else v) for k, v in out.items()}})
            msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": name,
                         "content": json.dumps(out, ensure_ascii=False, separators=(",", ":"))})
    if contract_grade.DEV[case_id]["family"] == "batch_merge":
        g = dict(contract_grade.oracles.grade_case(contract_grade.DEV[case_id], final_text,
                                                   process_receipt={"batch_events": batch_events},
                                                   normal_completion=(terminal == "natural_stop")))
    else:
        g = contract_grade.grade(case_id, ws, normal_completion=(terminal == "natural_stop"))
    rec = dict(case=case_id, seed=seed, arm=arm, terminal=terminal, responses=n, wall_s=round(time.time() - t0, 1),
               completion_tokens=usage["completion"], prompt_tokens=usage["prompt"],
               forced_turns=sum(1 for x in log if x.get("forced")), checks=sum(1 for x in log if x.get("tool") == "check_solution"),
               functional=g.get("functional_result_correct"), protocol=g.get("protocol_valid"),
               task_success=g.get("task_success"), reasons=g.get("reasons"))
    os.makedirs(out_dir, exist_ok=True)
    json.dump(dict(rec, grade=g, log=log, workspace={k: v.decode("utf-8", "replace") for k, v in ws.items()}),
              open(os.path.join(out_dir, f"{case_id}-{seed}-{arm}.json"), "w", encoding="utf-8"), ensure_ascii=False)
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    for case_id, seed, arm in json.load(open(a.plan))["order"]:
        if os.path.exists(os.path.join(a.out, f"{case_id}-{seed}-{arm}.json")):
            continue
        print(json.dumps(attempt(case_id, seed, arm, a.out)), flush=True)
