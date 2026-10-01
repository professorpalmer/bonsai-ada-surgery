"""Built-in code interpreter for the Bonsai server: an OpenAI-compatible proxy in front of llama-server.

  client --> proxy (:8081) --> llama-server (:8080)

For /v1/chat/completions requests the proxy offers the model a `run_python` tool. When the model calls it,
the proxy runs the code in CPython-on-WASI (tooling/wasi-python/sandbox.py: no host files, no network, no
processes, memory and time capped), appends the result, and asks the model again, until the model answers or
calls one of the client's own tools. The client sees one ordinary response.

  - default: on for requests WITHOUT client tools, off (pure passthrough) for requests that bring their own tools
    (E4: with client tools the model retypes paginated tool data into code and transcription errors cost tasks)
  - per request: "code_interpreter": true / false overrides the default
  - with the interpreter on and client tools present, client tool calls are returned as usual
  - the model's reasoning is kept on the internal turns (the server's template renders it)
  - the internal transcript is attached as "interpreter_trace" (runs, exit codes) for auditing
  - non-streaming only for now: stream=true requests are forwarded untouched (no interpreter)
Everything else (other paths, auth header) is forwarded verbatim.
"""
import argparse
import http.server
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "wasi-python"))
import sandbox  # noqa: E402

TOOL_NAME = "run_python"
TOOL = {"type": "function", "function": {
    "name": TOOL_NAME,
    "description": "Run a Python 3.12 program in an isolated sandbox (standard library only, no network, no "
                   "files outside its working directory, 10 second limit). Use it for exact computation, "
                   "counting, search or checking a result. Returns exit code, stdout and stderr.",
    "parameters": {"type": "object", "properties": {
        "code": {"type": "string", "description": "the complete program; print the results"},
        "stdin": {"type": "string", "description": "optional standard input"}}, "required": ["code"]}}}


FINAL_NUDGE = ("The code tool is no longer available. Using the results you already have, give your final answer "
               "now, in the format the original request asked for.")


def run_tool(args_json, timeout):
    try:
        args = json.loads(args_json) if isinstance(args_json, str) else args_json
        r = sandbox.run({"main.py": args.get("code", "")}, ["/work/main.py"],
                        stdin=(args.get("stdin") or "").encode("utf-8"), timeout=timeout)
        return {"exit_code": r["exit_code"], "timed_out": r["timed_out"],
                "stdout": r["stdout"][:12000].decode("utf-8", "replace"),
                "stderr": r["stderr"][-4000:].decode("utf-8", "replace")}
    except Exception as e:  # malformed arguments are reported to the model, never raised
        return {"error": f"tool call rejected: {e!r}"[:500]}


class Proxy(http.server.BaseHTTPRequestHandler):
    upstream = "http://127.0.0.1:8080"
    max_rounds = 8
    exec_timeout = 10.0
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
        client_tools = body.get("tools") or []
        # Default: offer the interpreter only to requests without client tools. Measured (E4): with client tools the
        # data lives in paginated tool results, the model must retype it into code, and transcription errors cost
        # 2 of 15 tasks (1 rescued). Clients with tools can opt in with "code_interpreter": true.
        wanted = body.pop("code_interpreter", None)
        enabled = (not client_tools) if wanted is None else bool(wanted)
        if not enabled or body.get("stream"):
            return self._reply(*self._forward("POST", json.dumps(body).encode()))
        if any(t.get("function", {}).get("name") == TOOL_NAME for t in client_tools):
            return self._reply(*self._forward("POST", json.dumps(body).encode()))   # client owns that name
        body["tools"] = client_tools + [TOOL]
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
                return self._reply(200, "application/json", json.dumps(resp).encode())
            am = {"role": "assistant", "content": m.get("content") or "", "tool_calls": calls}
            if m.get("reasoning_content"):
                am["reasoning_content"] = m["reasoning_content"]
            msgs.append(am)
            for c in ours:
                out = run_tool(c["function"]["arguments"], self.exec_timeout)
                trace.append({"round": rnd, "exit_code": out.get("exit_code"), "timed_out": out.get("timed_out"),
                              "stdout_head": (out.get("stdout") or "")[:200]})
                msgs.append({"role": "tool", "tool_call_id": c.get("id", ""), "name": TOOL_NAME,
                             "content": json.dumps(out, ensure_ascii=False)})
        return self._reply(500, "application/json", b'{"error":"interpreter loop ended without an answer"}')


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--upstream", default="http://127.0.0.1:8080")
    ap.add_argument("--max-rounds", type=int, default=8)
    a = ap.parse_args()
    Proxy.upstream, Proxy.max_rounds = a.upstream, a.max_rounds
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), Proxy)
    print(f"interpreter proxy on 127.0.0.1:{a.port} -> {a.upstream}", flush=True)
    srv.serve_forever()
