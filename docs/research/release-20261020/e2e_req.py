"""Requests for e2e.sh: a tool-list change, an appended turn (no line expected), an edited earlier message, an image."""
import json
import sys
import urllib.request

KEY = open(sys.argv[1]).read().strip()


def tool(name, desc):
    return {"type": "function", "function": {"name": name, "description": desc,
                                             "parameters": {"type": "object", "properties": {}}}}


TOOLS = [tool("read", "Read a file."), tool("mcp", "Call an MCP server. Servers: x64dbg."), tool("x64dbg_list", "List modules.")]
SYS = {"role": "system", "content": "You are a short assistant. " * 40}
U1 = {"role": "user", "content": "Say hello in three words."}


def ask(label, msgs, tools):
    body = {"messages": msgs, "tools": tools, "max_tokens": 24, "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            out = json.load(r)
        m = out["choices"][0]["message"]
        text = (m.get("content") or "").replace("\n", " ")[:60]
        print(f"{label}: 200 {text!r}")
        return {"role": "assistant", "content": m.get("content") or ""}
    except urllib.error.HTTPError as e:
        print(f"{label}: HTTP {e.code}")
        return {"role": "assistant", "content": ""}


a1 = ask("r1 first", [SYS, U1], TOOLS)
U2 = {"role": "user", "content": "Now say goodbye in three words."}
a2 = ask("r2 appended turn (no line expected)", [SYS, U1, a1, U2], TOOLS)
U3 = {"role": "user", "content": "And thank you in three words."}
a3 = ask("r3 x64dbg_list removed (line expected)", [SYS, U1, a1, U2, a2, U3], TOOLS[:2])
ask("r4 first user message edited (line expected)", [SYS, dict(U1, content="Say hi in three words."), a1, U2, a2, U3], TOOLS[:2])
IMG = {"role": "user", "content": [{"type": "text", "text": "What is this?"},
                                   {"type": "image_url", "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="}}]}
ask("r5 image, no mmproj (note line expected)", [SYS, IMG], TOOLS[:2])
