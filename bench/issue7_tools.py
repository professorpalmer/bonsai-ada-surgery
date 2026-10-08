"""Issue #7: decode at depth with and without `tools` in the request (agent clients send tools; the server then
runs a lazy grammar and turns off backend sampling). Same filler as quick_tps, so the prefix is cached after the
first request.   python bench/issue7_tools.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 138000"""
import argparse, json, urllib.request, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from quick_tps import filler, _headers

TOOLS = [{"type": "function", "function": {"name": "read", "description": "Read a file from the workspace.",
          "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
         {"type": "function", "function": {"name": "bash", "description": "Run a shell command.",
          "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}}]
PROMPTS = [("code", "Do not call any tool. Write a 300-line Python module implementing an LRU cache with tests. Code only."),
           ("prose", "Do not call any tool. Write a detailed 800 word essay on the history of the transistor.")]

def go(base, key, prompt, tools, think):
    body = {"model": "b", "messages": [{"role": "user", "content": prompt}], "max_tokens": 400, "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": think}}
    if tools: body["tools"] = TOOLS
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
    r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
    return r.get("timings", {}), r["choices"][0]

ap = argparse.ArgumentParser(); ap.add_argument("--base"); ap.add_argument("--key-file"); ap.add_argument("--depth", type=int, default=0)
a = ap.parse_args(); key = open(a.key_file).read().strip()
f = filler(a.base, key, a.depth) if a.depth else ""
# tools on the outside: a request with tools has a different prompt prefix, so each switch costs a full prefill
for tools in (False, True):
    for think in (False, True):
        for name, p in PROMPTS:
            t, c = go(a.base, key, f + p, tools, think)
            print(f"{name:<6} think={int(think)} tools={int(tools)}: decode {t.get('predicted_per_second', 0):6.1f} tok/s ({t.get('predicted_n')} tok, "
                  f"evaluated {t.get('prompt_n')}, finish {c.get('finish_reason')}, tool_calls {len(c['message'].get('tool_calls') or [])})", flush=True)
