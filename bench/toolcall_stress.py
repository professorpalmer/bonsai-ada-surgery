"""Tool-call syntax stress test for Bonsai 2 behind llama-server.

Reproduces the failure mode reported on the model (a dropped escape thousands of characters into a
code string inside a tool call) and separates two arms:

  A  native   `tools` in the request -> server applies the Qwen3-Coder XML PEG grammar; string
              parameters are raw text (no escaping). Success = server returns tool_calls whose
              payload is what was asked for (Python that compiles).
  B  json     no `tools`; the prompt asks for a Hermes-style JSON tool call in content. The model
              must escape the whole code payload inside a JSON string. Success = json.loads works
              and the extracted code compiles. This is the harness-imposed format the post
              measured against.

Usage: python bench/toolcall_stress.py --base http://127.0.0.1:8899 --n 12 --out artifacts/eval/toolcall_stress.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Create or overwrite a text file with the given content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Relative file path"},
                    "content": {"type": "string", "description": "Full file content"},
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "apply_edits",
            "description": "Apply a list of exact string replacements to files.",
            "parameters": {
                "type": "object",
                "properties": {
                    "edits": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "path": {"type": "string"},
                                "old": {"type": "string"},
                                "new": {"type": "string"},
                            },
                            "required": ["path", "old", "new"],
                        },
                    }
                },
                "required": ["edits"],
            },
        },
    },
]

# Payload-heavy tasks: long code with quotes, backslashes, regexes, f-strings, embedded JSON, newlines.
TASKS = [
    (
        "write_file",
        "Create `parser.py`: a complete Python module (at least 250 lines, no placeholders) implementing a "
        "tolerant INI/TOML-ish config parser. Requirements: a module docstring with examples that contain "
        "double quotes and backslashes; a regex table with at least 8 compiled patterns using raw strings and "
        "escapes like \\d, \\s, \\\", and \\\\; f-strings that nest both quote styles; a DEFAULTS dict "
        "containing a JSON string literal; a CLI `main()` with argparse; and a `__main__` guard. Write the "
        "whole file in one write_file call.",
    ),
    (
        "write_file",
        "Create `server_test.py`: a complete pytest module (at least 220 lines) that tests a tiny HTTP JSON API "
        "using urllib only. Include fixtures, at least 12 test functions, JSON request bodies written as Python "
        "dict literals AND as raw JSON strings with escaped quotes, a multi-line SQL string in a triple-quoted "
        "constant, Windows paths with backslashes, and a helper that builds curl commands with nested quoting. "
        "Write the whole file in one write_file call.",
    ),
    (
        "apply_edits",
        "Use apply_edits to make three edits to `app.py`. Each `old`/`new` must be a realistic multi-line "
        "Python snippet (6-15 lines each) containing string literals with double quotes, at least one regex with "
        "backslash escapes, and one f-string. Edit 1 replaces a logging setup block, edit 2 replaces a request "
        "validation function, edit 3 replaces a JSON response builder. Invent plausible original code for `old`.",
    ),
]

JSON_INSTRUCTIONS = (
    "You have this tool:\n{tool}\n\n"
    "Respond with EXACTLY one tool call and nothing else, in this format:\n"
    "<tool_call>\n{{\"name\": \"{name}\", \"arguments\": {{...}}}}\n</tool_call>\n"
    "The arguments object must be valid JSON; escape quotes, backslashes and newlines inside strings."
)


def post(base: str, body: dict, key: str | None, timeout: float = 900.0) -> dict:
    req = urllib.request.Request(
        base.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {key}"} if key else {})},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def python_compiles(src: str) -> tuple[bool, str]:
    try:
        compile(src, "<payload>", "exec")
        return True, ""
    except SyntaxError as e:
        return False, f"SyntaxError line {e.lineno}: {e.msg}"


def check_args(tool: str, args: dict) -> tuple[bool, str, int]:
    if tool == "write_file":
        content = args.get("content", "")
        ok, why = python_compiles(content)
        return ok, why, len(content)
    if tool == "apply_edits":
        edits = args.get("edits")
        if not isinstance(edits, list) or len(edits) < 3:
            return False, f"edits not a list of >=3 ({type(edits).__name__})", 0
        total = 0
        for i, e in enumerate(edits):
            if not isinstance(e, dict) or not all(isinstance(e.get(k), str) for k in ("path", "old", "new")):
                return False, f"edit {i} malformed", total
            total += len(e["old"]) + len(e["new"])
            for k in ("old", "new"):
                ok, why = python_compiles(e[k])
                if not ok:
                    return False, f"edit {i}.{k}: {why}", total
        return True, "", total
    return False, "unknown tool", 0


def run_native(base, key, tool, prompt, args_common):
    body = dict(args_common)
    body["messages"] = [{"role": "user", "content": prompt}]
    body["tools"] = TOOLS
    body["tool_choice"] = "auto"
    t0 = time.time()
    r = post(base, body, key)
    dt = time.time() - t0
    ch = r["choices"][0]
    msg = ch["message"]
    usage = r.get("usage", {})
    rec = {
        "arm": "A_native_grammar",
        "tool": tool,
        "finish": ch.get("finish_reason"),
        "completion_tokens": usage.get("completion_tokens"),
        "reasoning_chars": len(msg.get("reasoning_content") or ""),
        "seconds": round(dt, 1),
        "tps": round((usage.get("completion_tokens") or 0) / dt, 1) if dt > 0 else None,
    }
    calls = msg.get("tool_calls") or []
    rec["n_tool_calls"] = len(calls)
    if not calls:
        rec["parsed"] = False
        rec["why"] = "no tool_calls returned (content len %d)" % len(msg.get("content") or "")
        rec["content_head"] = (msg.get("content") or "")[:300]
        return rec
    fn = calls[0]["function"]
    rec["called"] = fn.get("name")
    try:
        args = json.loads(fn.get("arguments") or "{}")
    except json.JSONDecodeError as e:
        rec["parsed"] = False
        rec["why"] = f"server tool_calls arguments not JSON: {e}"
        return rec
    rec["parsed"] = True
    if rec["called"] != tool and rec["called"] in {t["function"]["name"] for t in TOOLS}:
        # a well-formed call to the other tool (seen: write_file to create app.py before editing it).
        # that is a planning choice, not a syntax failure; score the payload it did send.
        rec["other_tool"] = True
        tool = rec["called"]
    ok, why, n = check_args(tool, args)
    rec["payload_chars"] = n
    rec["payload_ok"] = ok
    rec["why"] = why
    if not ok:
        # keep enough of the call to tell a model bug from a server parsing artifact
        rec["args_keys"] = sorted(args.keys())
        rec["args_head"] = (fn.get("arguments") or "")[:600]
        rec["content_head"] = (msg.get("content") or "")[:300]
    return rec


def run_json(base, key, tool, prompt, args_common):
    tool_def = next(t for t in TOOLS if t["function"]["name"] == tool)
    sys_msg = JSON_INSTRUCTIONS.format(tool=json.dumps(tool_def), name=tool)
    body = dict(args_common)
    body["messages"] = [{"role": "system", "content": sys_msg}, {"role": "user", "content": prompt}]
    t0 = time.time()
    r = post(base, body, key)
    dt = time.time() - t0
    ch = r["choices"][0]
    msg = ch["message"]
    usage = r.get("usage", {})
    content = msg.get("content") or ""
    rec = {
        "arm": "B_json_in_content",
        "tool": tool,
        "finish": ch.get("finish_reason"),
        "completion_tokens": usage.get("completion_tokens"),
        "reasoning_chars": len(msg.get("reasoning_content") or ""),
        "seconds": round(dt, 1),
        "tps": round((usage.get("completion_tokens") or 0) / dt, 1) if dt > 0 else None,
        "content_chars": len(content),
    }
    m = re.search(r"<tool_call>\s*(\{.*\})\s*</tool_call>", content, re.S)
    raw = m.group(1) if m else None
    if raw is None:
        # model may have skipped the wrapper
        m2 = re.search(r"(\{.*\})", content, re.S)
        raw = m2.group(1) if m2 else None
        rec["wrapper_missing"] = True
    if raw is None:
        rec["parsed"] = False
        rec["why"] = "no JSON object found"
        rec["content_head"] = content[:300]
        return rec
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        rec["parsed"] = False
        rec["why"] = f"JSONDecodeError: {e.msg} at char {e.pos} of {len(raw)}"
        rec["json_chars"] = len(raw)
        rec["json_at_error"] = raw[max(0, e.pos - 200):e.pos + 60]
        return rec
    rec["parsed"] = True
    args = obj.get("arguments", obj)
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except json.JSONDecodeError as e:
            rec["parsed"] = False
            rec["why"] = f"arguments is a string that is not JSON: {e.msg}"
            return rec
    ok, why, n = check_args(tool, args)
    rec["payload_chars"] = n
    rec["payload_ok"] = ok
    rec["why"] = why
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8899")
    ap.add_argument("--key", default=None)
    ap.add_argument("--n", type=int, default=6, help="repetitions per task per arm")
    ap.add_argument("--arms", default="A,B")
    ap.add_argument("--max-tokens", type=int, default=9000)
    ap.add_argument("--effort", default="low", help="reasoning_effort template kwarg: low|medium|xhigh")
    ap.add_argument("--think", action="store_true",
                    help="leave thinking on (default off: the question is call syntax, and with thinking on the "
                         "model spent the whole 9000-token budget reasoning about a 250-line file)")
    ap.add_argument("--out", default="artifacts/eval/toolcall_stress.json")
    a = ap.parse_args()

    kwargs = {"reasoning_effort": a.effort} if a.think else {"enable_thinking": False}
    common = {
        "model": "bonsai",
        "temperature": 1.0,
        "top_p": 0.95,
        "top_k": 20,
        "max_tokens": a.max_tokens,
        "chat_template_kwargs": kwargs,
    }
    arms = [s.strip() for s in a.arms.split(",")]
    results = []
    for rep in range(a.n):
        for tool, prompt in TASKS:
            for arm in arms:
                fn = run_native if arm == "A" else run_json
                try:
                    rec = fn(a.base, a.key, tool, prompt, common)
                except Exception as e:  # noqa: BLE001
                    rec = {"arm": arm, "tool": tool, "parsed": False, "why": f"request error: {e!r}"}
                rec["rep"] = rep
                results.append(rec)
                flag = "OK " if rec.get("parsed") and rec.get("payload_ok") else ("PARSE-FAIL" if not rec.get("parsed") else "PAYLOAD-BAD")
                print(f"[{rep:2d}] {rec['arm']:<18} {tool:<11} {flag:<11} fin={rec.get('finish')} "
                      f"chars={rec.get('payload_chars', rec.get('json_chars', '-'))} tok={rec.get('completion_tokens')} "
                      f"think={rec.get('reasoning_chars')} tps={rec.get('tps')} {rec.get('why', '')[:90]}", flush=True)
                with open(a.out, "w", encoding="utf-8") as f:
                    json.dump(results, f, indent=1)

    print("\n== summary ==")
    for arm in sorted({r["arm"] for r in results}):
        rs = [r for r in results if r["arm"] == arm]
        parsed = sum(1 for r in rs if r.get("parsed"))
        good = sum(1 for r in rs if r.get("parsed") and r.get("payload_ok"))
        cut = sum(1 for r in rs if r.get("finish") == "length")
        chars = [r.get("payload_chars") for r in rs if r.get("payload_chars")]
        tps = [r["tps"] for r in rs if r.get("tps")]
        print(f"{arm:<18} n={len(rs)} parsed={parsed} payload_ok={good} cut_by_max_tokens={cut} "
              f"median_payload_chars={sorted(chars)[len(chars)//2] if chars else '-'} "
              f"mean_tps={sum(tps)/len(tps):.1f}" if tps else f"{arm} n={len(rs)} parsed={parsed}")


if __name__ == "__main__":
    sys.exit(main())
