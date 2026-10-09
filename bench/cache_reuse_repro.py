"""Issue #7 (2026-10-09): after a stop (ESC) and a new message, a long Pi session was read again from token 0.
Builds an agent-like session against a running server (layer off): a long tool list, a first user message, then
--steps synthetic agent steps (assistant reasoning + tool call, tool result), each sent as a request so the server
caches it and makes checkpoints. Then three follow-ups, each from the same session state, and for each the prompt
tokens the server read again (timings.prompt_n) and reused (timings.cache_n):
  a  a new user message at the end                        (expected: only the new tail is read)
  b  a long answer stopped after a few seconds, then (a)   (Pi's ESC)
  c  the first user message changed at its end             (what the old layer did; expected: read from there)
  d  the thinking removed from every assistant message      (a client that drops it after a stop)
    python bench/cache_reuse_repro.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag 0046
"""
import argparse, json, os, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from quick_tps import _headers  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", required=True)
ap.add_argument("--tools", type=int, default=110, help="number of tools (Pi + MCP: ~107 tools, ~104k characters)")
ap.add_argument("--steps", type=int, default=35)
ap.add_argument("--step-chars", type=int, default=6000, help="characters of each tool result")
ap.add_argument("--tag", default="")
ap.add_argument("--out", default="receipts/cache_reuse_repro.jsonl")
a = ap.parse_args()
key = open(a.key_file).read().strip()
WORDS = ["ledger", "harbor", "copper", "signal", "orchard", "granite", "lantern", "meadow", "falcon", "cipher"]


def tool(i):
    desc = " ".join(f"Option {k}: {WORDS[(i + k) % 10]} mode for records of kind {k}." for k in range(14))
    return {"type": "function", "function": {"name": f"mcp_tool_{i}", "description": f"Tool {i}. {desc}",
            "parameters": {"type": "object", "properties": {"q": {"type": "string", "description": "query"},
                                                             "limit": {"type": "integer"}}, "required": ["q"]}}}


TOOLS = [{"type": "function", "function": {"name": "bash", "description": "Run a shell command.",
          "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}}]
TOOLS += [tool(i) for i in range(a.tools)]


def post(body, timeout=3600):
    req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def ask(messages, max_tokens=8):
    t0 = time.time()
    r = post({"messages": messages, "tools": TOOLS, "max_tokens": max_tokens, "temperature": 0,
              "chat_template_kwargs": {"enable_thinking": False}})
    t = r.get("timings") or {}
    return {"prompt_n": t.get("prompt_n"), "cache_n": t.get("cache_n"), "wall": round(time.time() - t0, 1)}


def log(rec):
    rec = dict(tag=a.tag, **rec)
    print(json.dumps(rec), flush=True)
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def stopped_request(messages, seconds=6.0):
    """Start a streamed long answer and close the connection after a few seconds (a client's stop button)."""
    body = {"messages": messages, "tools": TOOLS, "max_tokens": 4000, "temperature": 0, "stream": True,
            "chat_template_kwargs": {"enable_thinking": True}}
    req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
    resp = urllib.request.urlopen(req, timeout=3600)
    t0, n = time.time(), 0
    while time.time() - t0 < seconds:
        if not resp.readline():
            break
        n += 1
    resp.close()
    return n


msgs = [{"role": "system", "content": "Eres Pi, un agente de programación. Usa las herramientas para trabajar en el repositorio."},
        {"role": "user", "content": "Compila el proyecto en build/ y dime si hay errores. Luego sigue con la tarea pendiente de anoche."}]
r = ask(msgs)
log({"event": "start", **r})
for s in range(a.steps):
    out = "\n".join(f"[{s}:{k}] cc -O2 -c src/{WORDS[k % 10]}_{k}.c -o build/{WORDS[k % 10]}_{k}.o   ok" for k in range(a.step_chars // 60))
    msgs.append({"role": "assistant", "content": "", "reasoning_content": f"Paso {s}: reviso la salida y sigo con el siguiente objetivo.",
                 "tool_calls": [{"id": f"call_{s}", "type": "function", "function": {"name": "bash", "arguments": json.dumps({"command": f"make -C build target_{s}"})}}]})
    msgs.append({"role": "tool", "tool_call_id": f"call_{s}", "content": out})
    r = ask(msgs)
    if s % 5 == 4 or s == a.steps - 1:
        log({"event": f"step {s + 1}", **r})
base = list(msgs)
new_user = {"role": "user", "content": "Espera, antes de seguir: usa también la opción -Wall."}

r = ask(base + [new_user]); log({"event": "a new message", **r})
ask(base)                                             # back to the session state
n = stopped_request(base + [new_user]); time.sleep(2)
r = ask(base + [new_user, {"role": "assistant", "content": "Entendido."}, {"role": "user", "content": "Sigue."}])
log({"event": f"b stopped answer ({n} stream lines) then a new message", **r})
ask(base)
changed = [dict(m) for m in base]
changed[1]["content"] += "\n\nBefore your final answer, run the program you wrote on the example given in the task and compare its output with the expected result; fix it if they differ."
r = ask(changed + [new_user]); log({"event": "c first user message changed at its end", **r})
ask(base)
stripped = [dict(m, reasoning_content="") if m.get("role") == "assistant" else m for m in base]
r = ask(stripped + [new_user]); log({"event": "d thinking removed from every assistant message", **r})
log({"event": "done", "prompt_tokens_total": r.get("prompt_n", 0) + (r.get("cache_n") or 0)})
