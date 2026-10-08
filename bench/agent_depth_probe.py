"""Agent-like decode at a given depth (issue #7): thinking on, tools in the request, greedy and sampled.
  python bench/agent_depth_probe.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 45000 --tag mtp
Prints decode tok/s, tokens, and the draft acceptance for each request."""
import argparse, json, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from quick_tps import filler, _headers  # noqa: E402

TOOLS = [{"type": "function", "function": {"name": "read", "description": "Read a file.",
          "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
         {"type": "function", "function": {"name": "bash", "description": "Run a shell command.",
          "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}}]
if os.environ.get("PROBE_MANY_TOOLS"):   # MCP-like: many tools with nested object parameters
    for k in range(int(os.environ["PROBE_MANY_TOOLS"])):
        TOOLS.append({"type": "function", "function": {"name": f"mcp_server{k // 10}_tool{k}", "description":
            f"Tool {k} of an MCP server: query, filter and update records of kind {k}.",
            "parameters": {"type": "object", "properties": {
                "query": {"type": "string", "description": "search text"},
                "filters": {"type": "object", "properties": {"field": {"type": "string"}, "op": {"type": "string",
                            "enum": ["eq", "ne", "lt", "gt", "contains"]}, "value": {"type": "string"}}},
                "limit": {"type": "integer", "minimum": 1, "maximum": 500},
                "fields": {"type": "array", "items": {"type": "string"}},
                "update": {"type": "object", "additionalProperties": {"type": "string"}}},
                "required": ["query"]}}})
ASKS = ["Do not call any tool. Explain step by step how you would add a retry with exponential backoff to an HTTP "
        "client in Python, then write the code.",
        "Do not call any tool. Plan a refactor of a 2,000-line Flask app into blueprints. List the steps and the risks."]
ARMS = [(n, s) for n, s in [("greedy", {"temperature": 0, "top_p": 1}),
        ("sampled", {"temperature": 0.6, "top_p": 0.95, "top_k": 20}),
        ("sampled-topk0", {"temperature": 0.6, "top_p": 0.95, "top_k": 0}),
        ("sampled-minp", {"temperature": 0.6, "top_p": 1.0, "top_k": 0, "min_p": 0.05})] if not os.environ.get("PROBE_ARMS") or n in os.environ["PROBE_ARMS"].split(",")]

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", required=True)
ap.add_argument("--depth", type=int, default=45000)
ap.add_argument("--tag", default="")
ap.add_argument("--out", default="receipts/agent_depth.jsonl")
a = ap.parse_args()
key = open(a.key_file).read().strip()
pre = filler(a.base, key, a.depth)
for arm, samp in ARMS:
    for i, q in enumerate(ASKS):
        body = dict(samp, messages=[{"role": "user", "content": pre + q}], tools=TOOLS, max_tokens=1500, seed=7,
                    chat_template_kwargs={"enable_thinking": True})
        req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
        r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
        t = r.get("timings") or {}
        acc = (t.get("draft_n_accepted") or 0) / max(1, t.get("draft_n") or 0) if t.get("draft_n") else None
        rec = {"tag": a.tag, "depth": a.depth, "arm": arm, "ask": i, "tps": round(t.get("predicted_per_second") or 0, 1),
               "n": t.get("predicted_n"), "evaluated": t.get("prompt_n"), "acceptance": None if acc is None else round(acc, 3)}
        print(json.dumps(rec), flush=True)
        with open(a.out, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
