"""Print what a client sends, without the prompt text: sampler settings, the number of tools and messages, and the
size of the tool list. Safe to paste into an issue.
    python bench/capture_summary.py logs/pi_requests.jsonl
"""
import json, sys

SKIP = {"messages", "tools", "prompt"}
for line in open(sys.argv[1], encoding="utf-8"):
    rec = json.loads(line)
    body = rec.get("body") or {}
    if not isinstance(body, dict) or "messages" not in body:
        continue
    settings = {k: v for k, v in body.items() if k not in SKIP}
    tools = body.get("tools") or []
    print(json.dumps({"path": rec.get("path"), "status": rec.get("status"), "settings": settings,
                      "tools": len(tools), "tool_chars": len(json.dumps(tools)),
                      "messages": len(body.get("messages") or [])}, ensure_ascii=False))
