"""Built-in code interpreter for the Bonsai server: an OpenAI-compatible proxy in front of llama-server.

  client --> layer (public port) --> llama-server (127.0.0.1, inner port)

For /v1/chat/completions requests the proxy offers the model a `run_python` tool. When the model calls it,
the proxy runs the code in CPython-on-WASI (layer/wasi-python/sandbox.py: no host files, no network, no
processes, memory and time capped), appends the result, and asks the model again, until the model answers or
calls one of the client's own tools. The client sees one ordinary response.

  - default: on for requests WITHOUT client tools, off (pure passthrough) for requests that bring their own tools
    (E4: with client tools the model retypes paginated tool data into code and transcription errors cost tasks)
  - per request: "code_interpreter": true / false overrides the default
  - with the interpreter on and client tools present, client tool calls are returned as usual
  - the model's reasoning is kept on the internal turns (the server's template renders it)
  - the internal transcript is attached as "interpreter_trace" (runs, exit codes) for auditing
  - streaming requests get the same loop: reasoning and answer tokens are relayed as they arrive, the
    run_python calls are withheld and executed, and the stream continues with the next round
Everything else (other paths, auth header) is forwarded verbatim.
"""
import argparse
import hmac
import http.server
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sandbox_path  # noqa: E402,F401
import sandbox  # noqa: E402
import apicards_v2 as apicards  # noqa: E402  (E9b: v2 docstring cards adopted)
import apilint  # noqa: E402

TOOL_NAME = "run_python"
TOOL = {"type": "function", "function": {
    "name": TOOL_NAME,
    "description": "Run a Python 3.12 program in an isolated sandbox (standard library only, no network, no "
                   "files outside its working directory, 10 second limit). Use it for exact computation, "
                   "counting, search or checking a result. Returns exit code, stdout and stderr.",
    "parameters": {"type": "object", "properties": {
        "code": {"type": "string", "description": "the complete program; print the results"},
        "stdin": {"type": "string", "description": "optional standard input"}}, "required": ["code"]}}}
INPUT_FILE = "input.txt"
INPUT_NOTE = (" The full text of the user's messages in this conversation is in the file " + INPUT_FILE +
              " in the working directory: read the data from there instead of retyping it.")


def tool_spec(with_input):
    if not with_input:
        return TOOL
    t = json.loads(json.dumps(TOOL))
    t["function"]["description"] += INPUT_NOTE
    return t


def user_text(msgs):
    """The user's own words (string contents of user messages), for the sandbox input file."""
    parts = []
    for m in msgs:
        if m.get("role") == "user":
            c = m.get("content")
            if isinstance(c, str):
                parts.append(c)
            elif isinstance(c, list):
                parts.extend(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
    return (chr(10) + chr(10)).join(parts)


FINAL_NUDGE = ("The code tool is no longer available. Using the results you already have, give your final answer "
               "now, in the format the original request asked for.")


def run_tool(args_json, timeout, extra_files=None):
    try:
        args = json.loads(args_json) if isinstance(args_json, str) else args_json
        files = dict(extra_files or {})
        files["main.py"] = args.get("code", "")
        r = sandbox.run(files, ["/work/main.py"], stdin=(args.get("stdin") or "").encode("utf-8"), timeout=timeout)
        return {"exit_code": r["exit_code"], "timed_out": r["timed_out"], "code_chars": len(args.get("code", "") or ""),
                "stdout": r["stdout"][:12000].decode("utf-8", "replace"),
                "stderr": r["stderr"][-4000:].decode("utf-8", "replace")}
    except Exception as e:  # malformed arguments are reported to the model, never raised
        return {"error": f"tool call rejected: {e!r}"[:500]}



def apply_lint(msgs):
    """Check Python code in the model's earlier tool calls against the real runtime and append any findings to the
    matching tool result. Deterministic for a given history, so the rendered prefix stays stable across turns."""
    findings = {}
    for m in msgs:
        if m.get("role") != "assistant":
            continue
        for c in m.get("tool_calls") or []:
            try:
                args = json.loads(c["function"]["arguments"]) if isinstance(c["function"]["arguments"], str)                     else c["function"]["arguments"]
            except (ValueError, KeyError, TypeError):
                continue
            if not isinstance(args, dict):
                continue
            name = next((v for k, v in args.items() if k in ("path", "file", "filename", "file_path") and isinstance(v, str)), "")
            for k, v in args.items():
                if apilint.looks_like_python(name if k != "path" else "", v) and k not in ("path", "file", "filename", "file_path"):
                    w = apilint.lint(v)
                    if w:
                        findings[c.get("id", "")] = apilint.format_warnings(w)
    if not findings:
        return msgs, 0
    out, n = [], 0
    for m in msgs:
        if m.get("role") == "tool" and m.get("tool_call_id") in findings and isinstance(m.get("content"), str)                 and "[API check by the server" not in m["content"]:
            m = dict(m, content=m["content"] + chr(10) + findings[m["tool_call_id"]])
            n += 1
        out.append(m)
    return out, n


PREFER = ("Use the library functions listed above instead of implementing these formats or algorithms by hand; "
          "they already implement them correctly.")


REPAIR_NOTE = ("[Server note: this run failed. Before your next tool call, reason step by step about the exact cause "
               "shown above and check that your change fixes it.]")


def tool_failed(content):
    """A run_python / run-style tool result that reports failure (exit code, timeout or a traceback)."""
    try:
        o = json.loads(content)
    except (TypeError, ValueError):
        return False
    if not isinstance(o, dict):
        return False
    if o.get("timed_out") or (isinstance(o.get("exit_code"), int) and o["exit_code"] != 0):
        return True
    return "Traceback (most recent call last)" in str(o.get("stderr") or "")


def apply_repair_note(msgs):
    """E14: append one fixed sentence to every failing tool result. Measured problem: after a failing test the model
    reasons a median of ~300 characters before its next step (bundle traces). Deterministic for a given history."""
    out, n = [], 0
    for m in msgs:
        if (m.get("role") == "tool" and isinstance(m.get("content"), str) and REPAIR_NOTE not in m["content"]
                and tool_failed(m["content"])):
            m = dict(m, content=m["content"] + chr(10) + REPAIR_NOTE)
            n += 1
        out.append(m)
    return out, n


FINISH_NOTE = ("Before your final answer, run the program you wrote on the example given in the task and compare its "
               "output with the expected result; fix it if they differ.")


def apply_finish_note(body, msgs):
    """E15: one fixed sentence at the end of the first user message of a coding request that offers a run tool.
    Measured problem (E11): solutions that reject even the disclosed example, and the model ends its turn anyway."""
    tools = body.get("tools") or []
    if not any(apicards.CODING_TOOL_RE.search(t.get("function", {}).get("name", "")) for t in tools):
        return msgs, 0
    for i, m in enumerate(msgs):
        if m.get("role") == "user" and isinstance(m.get("content"), str):
            if FINISH_NOTE in m["content"]:
                return msgs, 0
            return msgs[:i] + [dict(m, content=m["content"] + chr(10) + chr(10) + FINISH_NOTE)] + msgs[i + 1:], 1
    return msgs, 0


def apply_cards(body, msgs):
    """Append API cards for the modules a coding request involves to the END of the first user message, followed by
    one generic sentence. Measured (E9/E9b): the same cards in the system message did not help (2/6); at the end of
    the user message with the sentence they matched hand-written notes (6/6). The first user message is used so the
    rendered prefix stays stable across the turns of a tool loop."""
    for i, m in enumerate(msgs):
        if m.get("role") == "user" and isinstance(m.get("content"), str):
            if "Reference: exact APIs of the Python modules" in m["content"]:
                return msgs, 0
            # cards depend only on the request up to the first user message, so they are identical on every turn
            text = apicards.cards_for_request(dict(body, messages=msgs[:i + 1]))
            if not text:
                return msgs, 0
            add = chr(10) + chr(10) + text + chr(10) + chr(10) + PREFER
            return msgs[:i] + [dict(m, content=m["content"] + add)] + msgs[i + 1:], len(add)
    return msgs, 0


class Proxy(http.server.BaseHTTPRequestHandler):
    upstream = "http://127.0.0.1:8080"
    max_rounds = 8
    cards = True
    lint = True
    exec_timeout = 10.0
    api_key = None        # when set, chat requests are checked here before any work is done
    finish_note = True    # default for "finish_note": run-on-the-example sentence for coding requests (E15: adopted)
    repair_note = False   # default for "repair_note": a fixed sentence on failing tool results (E14 pending)
    input_file = True     # default for "input_file": the user's text as input.txt for run_python (E12: adopted)
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):
        sys.stderr.write("[proxy] " + (fmt % a) + "\n")

    def _forward(self, method, body=None):
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
        req = urllib.request.Request(self.upstream + self.path, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=7200) as r:
                return r.status, r.headers.get("Content-Type", "application/json"), r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type", "application/json"), e.read()

    def _stream(self, method, body):
        """Relay a streamed (SSE) response as it arrives."""
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
        req = urllib.request.Request(self.upstream + self.path, data=body, method=method, headers=headers)
        try:
            r = urllib.request.urlopen(req, timeout=7200)
        except urllib.error.HTTPError as e:
            return self._reply(e.code, e.headers.get("Content-Type", "application/json"), e.read())
        self.send_response(r.status)
        self.send_header("Content-Type", r.headers.get("Content-Type", "text/event-stream"))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        try:
            while True:
                chunk = r.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            r.close()

    def _open_stream(self, body):
        headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type")}
        req = urllib.request.Request(self.upstream + self.path, data=json.dumps(body).encode(), method="POST", headers=headers)
        return urllib.request.urlopen(req, timeout=7200)

    def _stream_interpreter(self, body, client_tools, with_input=False, extra=None):
        """The interpreter loop for a streamed request. Everything the model streams is relayed as it arrives except
        run_python tool-call deltas, which are collected, executed in the sandbox, and followed by the next round on
        the same client connection. Only used for requests without client tools."""
        msgs = list(body["messages"])
        body["tools"] = [tool_spec(with_input)]
        started = False
        # usage: ask the server for it on every round, sum the rounds, and emit one usage chunk at the end
        # when the client asked for one (stream_options.include_usage); otherwise none, as the client expects.
        client_usage = bool((body.get("stream_options") or {}).get("include_usage"))
        body["stream_options"] = dict(body.get("stream_options") or {}, include_usage=True)
        total = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}

        def send(line):
            self.wfile.write(line + b"\n\n")
            self.wfile.flush()

        try:
            for rnd in range(self.max_rounds + 1):
                body["messages"] = msgs
                if rnd == self.max_rounds:            # last round: no more code, answer now
                    body.pop("tools", None)
                    body.pop("tool_choice", None)
                    body["messages"] = msgs + [{"role": "user", "content": FINAL_NUDGE}]
                try:
                    r = self._open_stream(body)
                except urllib.error.HTTPError as e:
                    if not started:
                        return self._reply(e.code, e.headers.get("Content-Type", "application/json"), e.read())
                    return
                if not started:
                    self.send_response(200)
                    self.send_header("Content-Type", r.headers.get("Content-Type", "text/event-stream"))
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.close_connection = True
                    started = True
                calls, held, content, reasoning, template = {}, [], [], [], None
                with r:
                    for line in r:
                        line = line.rstrip(b"\r\n")
                        if not line.startswith(b"data:"):
                            continue
                        payload = line[5:].strip()
                        if payload == b"[DONE]":
                            held.append(line)
                            break
                        try:
                            ev = json.loads(payload)
                        except ValueError:
                            send(line)
                            continue
                        ch = (ev.get("choices") or [{}])[0]
                        delta = ch.get("delta") or {}
                        if template is None and ev.get("id"):
                            template = {k: ev[k] for k in ("id", "model", "created", "object", "system_fingerprint") if k in ev}
                        if ev.get("usage") and not ev.get("choices"):
                            for k in total:
                                total[k] += ev["usage"].get(k, 0) or 0
                            continue                   # replaced by one summed usage chunk at the end
                        if delta.get("tool_calls"):
                            for tc in delta["tool_calls"]:
                                c = calls.setdefault(tc.get("index", 0), {"id": "", "type": "function", "function": {"name": "", "arguments": ""}})
                                c["id"] = tc.get("id") or c["id"]
                                f = tc.get("function") or {}
                                c["function"]["name"] += f.get("name") or ""
                                c["function"]["arguments"] += f.get("arguments") or ""
                            held.append(line)
                            continue
                        if ch.get("finish_reason") == "tool_calls" or (calls and not ev.get("choices")):
                            held.append(line)      # the finish chunk (and a trailing usage chunk) of a tool round
                            continue
                        if isinstance(delta.get("content"), str):
                            content.append(delta["content"])
                        if isinstance(delta.get("reasoning_content"), str):
                            reasoning.append(delta["reasoning_content"])
                        send(line)
                ordered = [calls[i] for i in sorted(calls)]
                ours = [c for c in ordered if c["function"]["name"] == TOOL_NAME]
                if not ours or len(ours) != len(ordered) or rnd == self.max_rounds:
                    done = [l for l in held if l.strip() == b"data: [DONE]"]
                    for line in held:               # final answer (or a call that is not ours): hand everything back
                        if line.strip() != b"data: [DONE]":
                            send(line)
                    if client_usage:
                        ev = dict(template or {"object": "chat.completion.chunk"}, choices=[], usage=total)
                        send(b"data: " + json.dumps(ev).encode())
                    for line in done:
                        send(line)
                    return
                am = {"role": "assistant", "content": "".join(content), "tool_calls": ordered}
                if reasoning:
                    am["reasoning_content"] = "".join(reasoning)
                msgs.append(am)
                for c in ours:
                    out = run_tool(c["function"]["arguments"], self.exec_timeout, extra)
                    msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": TOOL_NAME,
                                 "content": json.dumps(out, ensure_ascii=False)})
                    note = "[run_python: " + ("timed out" if out.get("timed_out") else "exit " + str(out.get("exit_code", "rejected"))) + "]"
                    ev = dict(template or {"object": "chat.completion.chunk"},
                              choices=[{"index": 0, "delta": {"reasoning_content": chr(10) + note + chr(10)}, "finish_reason": None}])
                    send(b"data: " + json.dumps(ev).encode())
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            return

    def _reply(self, status, ctype, data):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._reply(*self._forward("GET"))

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._reply(*self._forward("POST", raw))
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            return self._reply(*self._forward("POST", raw))
        if self.api_key:
            given = self.headers.get("Authorization", "")
            if not hmac.compare_digest(given.encode("utf-8", "replace"), ("Bearer " + self.api_key).encode()):
                return self._reply(*self._forward("POST", raw))   # let the server produce its own 401; do no work here
        # server-side preprocessing for every chat request (streamed or not, with or without client tools)
        msgs0 = list(body.get("messages") or [])
        info = {}
        want_input = body.pop("input_file", None)
        with_input = self.input_file if want_input is None else bool(want_input)
        extra = {INPUT_FILE: user_text(msgs0)} if with_input else None
        try:
            if self.lint and body.pop("api_lint", True) is not False:
                msgs0, info["lint_notes"] = apply_lint(msgs0)
            if self.cards and body.pop("api_cards", True) is not False:
                msgs0, info["card_chars"] = apply_cards(body, msgs0)
            want_fin = body.pop("finish_note", None)
            if self.finish_note if want_fin is None else bool(want_fin):
                msgs0, info["finish_note"] = apply_finish_note(body, msgs0)
            want_note = body.pop("repair_note", None)
            if self.repair_note if want_note is None else bool(want_note):
                msgs0, info["repair_notes"] = apply_repair_note(msgs0)
        except Exception as e:   # preprocessing must never break a request
            self.log_message("preprocess failed: %r", e)
            msgs0 = list(body.get("messages") or [])
        body["messages"] = msgs0
        client_tools = body.get("tools") or []
        # Default: offer the interpreter only to requests without client tools. Measured (E4): with client tools the
        # data lives in paginated tool results, the model must retype it into code, and transcription errors cost
        # 2 of 15 tasks (1 rescued). Clients with tools can opt in with "code_interpreter": true.
        wanted = body.pop("code_interpreter", None)
        enabled = (not client_tools) if wanted is None else bool(wanted)
        ours_taken = any(t.get("function", {}).get("name") == TOOL_NAME for t in client_tools)
        if body.get("stream"):
            if enabled and not client_tools and not ours_taken:
                return self._stream_interpreter(body, client_tools, with_input, extra)
            return self._stream("POST", json.dumps(body).encode())
        if not enabled:
            return self._reply(*self._forward("POST", json.dumps(body).encode()))
        if any(t.get("function", {}).get("name") == TOOL_NAME for t in client_tools):
            return self._reply(*self._forward("POST", json.dumps(body).encode()))   # client owns that name
        body["tools"] = client_tools + [tool_spec(with_input)]
        msgs = list(body["messages"])
        trace, usage_total = [], {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
        for rnd in range(self.max_rounds + 1):
            body["messages"] = msgs
            if rnd == self.max_rounds:            # last round: no more code, answer now
                body["tools"] = client_tools or None
                if not client_tools:
                    body.pop("tools", None)
                    body.pop("tool_choice", None)
                # E7 seed 411: with tools merely removed, the model can end without an answer. Say it plainly.
                body["messages"] = msgs + [{"role": "user", "content": FINAL_NUDGE}]
            status, ctype, data = self._forward("POST", json.dumps(body).encode())
            if status != 200:
                return self._reply(status, ctype, data)
            resp = json.loads(data)
            for k in usage_total:
                usage_total[k] += (resp.get("usage") or {}).get(k, 0)
            m = resp["choices"][0]["message"]
            calls = m.get("tool_calls") or []
            ours = [c for c in calls if c["function"]["name"] == TOOL_NAME]
            if not ours or len(ours) != len(calls):   # final answer, or a client tool call: hand back
                if ours:                               # mixed: drop our calls, keep the client's
                    m["tool_calls"] = [c for c in calls if c["function"]["name"] != TOOL_NAME]
                resp["usage"] = usage_total
                resp["interpreter_trace"] = trace
                resp["layer"] = info
                return self._reply(200, "application/json", json.dumps(resp).encode())
            am = {"role": "assistant", "content": m.get("content") or "", "tool_calls": calls}
            if m.get("reasoning_content"):
                am["reasoning_content"] = m["reasoning_content"]
            msgs.append(am)
            for c in ours:
                out = run_tool(c["function"]["arguments"], self.exec_timeout, extra)
                trace.append({"round": rnd, "exit_code": out.get("exit_code"), "timed_out": out.get("timed_out"),
                              "code_chars": out.get("code_chars"),
                              "stdout_head": (out.get("stdout") or "")[:200]})
                msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": TOOL_NAME,
                             "content": json.dumps(out, ensure_ascii=False)})
        return self._reply(500, "application/json", b'{"error":"interpreter loop ended without an answer"}')


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--upstream", default="http://127.0.0.1:8080")
    ap.add_argument("--max-rounds", type=int, default=8)
    ap.add_argument("--no-cards", action="store_true")
    ap.add_argument("--no-lint", action="store_true")
    ap.add_argument("--no-finish-note", action="store_true", help="do not append the run-on-the-example sentence to coding requests")
    ap.add_argument("--repair-note", action="store_true", help="append a fixed sentence to failing tool results by default")
    ap.add_argument("--no-input-file", action="store_true", help="do not give run_python the user's text as input.txt")
    a = ap.parse_args()
    Proxy.api_key = os.environ.get("BONSAI_LAYER_KEY") or None
    Proxy.upstream, Proxy.max_rounds = a.upstream, a.max_rounds
    Proxy.cards, Proxy.lint = not a.no_cards, not a.no_lint
    Proxy.input_file = not a.no_input_file
    Proxy.repair_note = a.repair_note
    Proxy.finish_note = not a.no_finish_note
    srv = http.server.ThreadingHTTPServer((a.host, a.port), Proxy)
    print(f"bonsai layer on {a.host}:{a.port} -> {a.upstream}", flush=True)
    srv.serve_forever()
