"""Issue #4 probe: does MTP drafting still pay when the request carries tools (a server grammar)?

Sends the same long agent-style turn three ways against the inner server and reads the server's own timings:
  plain      no tools
  tools      an agent-style tools array (6 functions), tool_choice auto, thinking off (Hermes-style)
  tools+think the same with thinking on (medium)
Reports decode tok/s and, from the server log if given, the draft acceptance lines. Run once with the product
(MTP on) and once with BONSAI_SPEC=0 to compare.

    python bench/grammar_spec_probe.py --base http://127.0.0.1:18080 --key-file artifacts/api_key.txt --log logs/issue_serve.err
"""
import argparse, json, re, time, urllib.request

TOOLS = [
    {"type": "function", "function": {"name": "read_file", "description": "Read a file from the workspace", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "write_file", "description": "Write a file", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
    {"type": "function", "function": {"name": "run_shell", "description": "Run a shell command", "parameters": {"type": "object", "properties": {"command": {"type": "string"}, "timeout": {"type": "integer"}}, "required": ["command"]}}},
    {"type": "function", "function": {"name": "search_web", "description": "Search the web", "parameters": {"type": "object", "properties": {"query": {"type": "string"}, "max_results": {"type": "integer"}}, "required": ["query"]}}},
    {"type": "function", "function": {"name": "list_dir", "description": "List a directory", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "memory_add", "description": "Store a note", "parameters": {"type": "object", "properties": {"text": {"type": "string"}, "tags": {"type": "array", "items": {"type": "string"}}}, "required": ["text"]}}},
]
SYSTEM = "You are a coding agent working in a repository. Think step by step and answer in prose; do not call tools for this question."
PROMPT = ("Explain, in about 600 words, how you would refactor a 3,000-line Python module that mixes argument parsing, "
          "file IO, a job scheduler and HTTP handlers into a package, including the order of steps, the tests you would "
          "write first, and the risks at each step. Prose only, no code blocks.")

def go(base, key, body, tag):
    H = {"Authorization": "Bearer " + key, "Content-Type": "application/json"}
    t = time.time()
    r = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(), H), timeout=1800).read())
    tm = r.get("timings", {}); ch = r["choices"][0]
    print(f"{tag:12} decode {tm.get('predicted_per_second', 0):6.1f} tok/s  prefill {tm.get('prompt_per_second', 0):6.0f}  n={tm.get('predicted_n')}  finish={ch.get('finish_reason')}  tool_calls={len(ch['message'].get('tool_calls') or [])}  wall {time.time()-t:.0f}s", flush=True)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--base", default="http://127.0.0.1:18080"); ap.add_argument("--key-file", default="artifacts/api_key.txt"); ap.add_argument("--log", default="")
    ap.add_argument("--n", type=int, default=600)
    a = ap.parse_args(); key = open(a.key_file, encoding="utf-8").read().strip()
    msgs = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": PROMPT}]
    mark = 0
    if a.log:
        mark = len(open(a.log, encoding="utf-8", errors="replace").read())
    base_body = {"model": "bonsai-2-27b", "messages": msgs, "max_tokens": a.n, "temperature": 0.7, "top_p": 0.95}
    go(a.base, key, {**base_body, "chat_template_kwargs": {"enable_thinking": False}}, "plain")
    go(a.base, key, {**base_body, "tools": TOOLS, "tool_choice": "auto", "chat_template_kwargs": {"enable_thinking": False}}, "tools")
    go(a.base, key, {**base_body, "tools": TOOLS, "tool_choice": "auto", "max_tokens": 4096}, "tools+think")
    if a.log:
        tail = open(a.log, encoding="utf-8", errors="replace").read()[mark:]
        for m in re.finditer(r"draft acceptance = ([0-9.]+) \(\s*(\d+) accepted /\s*(\d+) generated\)", tail):
            print("   server:", m.group(0))
        for line in tail.splitlines():
            if "grammar" in line.lower() or "backend sampling" in line.lower():
                print("   server:", line.strip()[:160])

if __name__ == "__main__":
    main()
