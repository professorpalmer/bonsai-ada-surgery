"""Offline test: the layer says where a chat request stops repeating the previous one (issue #7), and a vision probe
that fails after a good answer keeps that answer.
python tests/test_prefix_log.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "layer"))
import bonsai_layer as L  # noqa: E402


def tool(name, desc="d"):
    return {"type": "function", "function": {"name": name, "description": desc, "parameters": {"type": "object"}}}


SYS = {"role": "system", "content": "You are an agent."}
U1 = {"role": "user", "content": "continue"}
A1 = {"role": "assistant", "content": "", "reasoning_content": "long thinking", "tool_calls": [
    {"id": "c1", "type": "function", "function": {"name": "mcp", "arguments": "{}"}}]}
T1 = {"role": "tool", "tool_call_id": "c1", "content": "Server not available"}
TOOLS = [tool("read"), tool("mcp", "servers: x64dbg"), tool("x64dbg_list")]

fails = 0


def check(name, got, want):
    global fails
    ok = (want is None and got is None) or (want is not None and got is not None and want in got)
    print(("PASS " if ok else "FAIL ") + name + ": " + repr(got))
    fails += 0 if ok else 1


def s(msgs, tools=TOOLS):
    return L.prompt_summary({"messages": msgs, "tools": tools})


base = s([SYS, U1])
check("first request", L.prefix_change(None, base), None)
check("a turn added at the end", L.prefix_change(base, s([SYS, U1, A1, T1])), None)
no_reason = dict(A1)
no_reason.pop("reasoning_content")
check("the client drops old reasoning", L.prefix_change(s([SYS, U1, A1, T1]), s([SYS, U1, no_reason, T1])),
      "the reasoning of message 2 (assistant) changed or was left out")
nop = {"preserve_thinking": False}
check("old reasoning dropped, preserve_thinking false", L.prefix_change(
    L.prompt_summary({"messages": [SYS, U1, A1, T1], "tools": TOOLS, "chat_template_kwargs": nop}),
    L.prompt_summary({"messages": [SYS, U1, no_reason, T1], "tools": TOOLS, "chat_template_kwargs": nop})), None)
check("a tool removed", L.prefix_change(base, s([SYS, U1, A1], TOOLS[:2])), "removed x64dbg_list")
check("a tool description changed", L.prefix_change(base, s([SYS, U1], [tool("read"), tool("mcp", "servers: none"), tool("x64dbg_list")])),
      "changed mcp")
check("tools in another order", L.prefix_change(base, s([SYS, U1], TOOLS[::-1])), "another order")
check("a tool added", L.prefix_change(base, s([SYS, U1], TOOLS + [tool("new")])), "added new")
check("an earlier message edited", L.prefix_change(s([SYS, U1, A1, T1]), s([SYS, U1, A1, dict(T1, content="x")])),
      "message 3 (tool) changed (4 of 5 parts")
check("the system message changed", L.prefix_change(base, s([dict(SYS, content="other"), U1])), "message 0 (system) changed")
check("a shorter request", L.prefix_change(s([SYS, U1, A1, T1]), s([SYS, U1])), "fewer parts")

# The opt-in excerpt (issue #7: a client rewrote its developer message in the middle of a session).
DEV1 = {"role": "developer", "content": "You are pi.\nTools: read, write.\nMCP servers: engram, x64dbg.\nBe brief."}
DEV2 = {"role": "developer", "content": "You are pi.\nTools: read, write.\nMCP servers: engram, x64dbg, git.\nBe brief."}
b1 = {"messages": [DEV1, U1, A1, T1], "tools": TOOLS}
b2 = {"messages": [DEV2, U1, A1, T1], "tools": TOOLS}
d = L.first_diff(L.prompt_texts(b1), L.prompt_texts(b2))
ok = d is not None and d[0] == 0 and d[1] == DEV1["content"].index(".\nBe") and ", git" in d[3]
check("excerpt: the first changed part and offset", "yes" if ok else "no: %r" % (d,), "yes")
check("excerpt: no change, no excerpt", L.first_diff(L.prompt_texts(b1), L.prompt_texts(b1)), None)
d3 = L.first_diff(L.prompt_texts(b1), L.prompt_texts(dict(b1, tools=TOOLS[:2])))
check("excerpt: a tool change points at the tool list part", "yes" if d3 and d3[0] == 1 else "no: %r" % (d3,), "yes")

# The vision probe: a good "no" answer stays when a later probe fails (a busy server can miss the 5 s timeout).
P = L.Proxy.__new__(L.Proxy)
P.upstream = "http://127.0.0.1:1"   # nothing listens: every probe fails
P.api_key = None
L.Proxy._vision, L.Proxy._vision_at = None, 0.0
check("no answer yet: assume vision (no change)", "yes" if P._has_vision() else "no", "yes")
L.Proxy._vision, L.Proxy._vision_at = False, 0.0   # the last answer was "no vision"; the minute is over
check("a failed probe keeps the last answer", "yes" if P._has_vision() else "no", "no")

print("ALL PASS" if not fails else "%d FAIL" % fails)
sys.exit(1 if fails else 0)
