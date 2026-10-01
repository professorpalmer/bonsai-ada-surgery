"""Functional check of --reasoning-cache on a running server (BONSAI_BASE, default loopback).

1. Ask a tool-using question; the server generates reasoning + a tool call with a server-made id.
2. Send the conversation back WITHOUT reasoning_content (as OpenAI clients do) to /apply-template.
3. PASS if the rendered prompt contains the generated reasoning (cache on) / an empty think block (cache off).
Also checks that an unknown tool-call id is left alone (no cross-conversation leakage).
"""
import json
import sys

from run import post
import envs

q = [{"role": "system", "content": "Use the tools."},
     {"role": "user", "content": "List the tables in the workspace."}]
body = dict(model="bonsai-2-27b", messages=q, tools=envs.TOOLS, temperature=0.0, max_tokens=2048,
            reasoning_format="deepseek", chat_template_kwargs={"reasoning_effort": "medium"})
r = post("/v1/chat/completions", body, 600)
m = r["choices"][0]["message"]
rc = (m.get("reasoning_content") or "").strip()
calls = m.get("tool_calls") or []
assert calls and rc, ("need a tool call with reasoning to test", m)
back = {"role": "assistant", "content": m.get("content") or "", "tool_calls": calls}      # reasoning dropped
tool = {"role": "tool", "tool_call_id": calls[0]["id"], "name": calls[0]["function"]["name"], "content": "{\"tables\": []}"}
rendered = post("/apply-template", dict(body, messages=q + [back, tool]), 60)["prompt"]
restored = rc[:200] in rendered
empty = "<think>\n\n</think>" in rendered

# a foreign id must not pick up anything
foreign = dict(back, tool_calls=[dict(calls[0], id="not-a-server-id-0000000000000000")])
r2 = post("/apply-template", dict(body, messages=q + [foreign, dict(tool, tool_call_id="not-a-server-id-0000000000000000")]), 60)["prompt"]
leak = rc[:200] in r2

res = {"reasoning_chars": len(rc), "tool_call_id": calls[0]["id"], "restored": restored, "empty_think": empty,
       "foreign_id_leak": leak}
print(json.dumps(res))
mode = sys.argv[1] if len(sys.argv) > 1 else "on"
ok = (restored and not empty and not leak) if mode == "on" else (not restored and empty)
print("PASS" if ok else "FAIL", mode)
sys.exit(0 if ok else 1)
