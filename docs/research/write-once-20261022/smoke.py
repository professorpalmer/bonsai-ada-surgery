"""Feasibility (exploration, not gated): continue_final_message on this engine.
F1 content continuation: the thinking closed with a given plan, the model writes the answer (chat, and with write_file).
F2 reasoning continuation: the thinking starts with a steering prefix in the model's voice."""
import json, re, sys, time, urllib.request

INNER = "http://127.0.0.1:18080"
KEY = open(sys.argv[1]).read().strip()
OUT = sys.argv[2]
WF = {"type": "function", "function": {"name": "write_file", "description": "Write a text file in the workspace.",
      "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                     "required": ["path", "content"]}}}
SYS = {"role": "system", "content": "You are a helpful assistant."}
PLAN = ("The user wants a 1,500-word short story about a lighthouse keeper who receives letters from someone who does not "
        "exist yet. Plan: keeper Tomas, 1890s, a storm island. The letters come from his granddaughter, not yet born; they "
        "know things he has not lived. Arc: doubt, then hope, then he writes back and leaves the letters for her. Tone: quiet, "
        "concrete. Five scenes. About 1,500 words. I will write it once now, in the answer.")
STEER = ("I will plan briefly here: the main idea, the people, the shape and the tone, in a few short lines. I will not "
         "write the text here and I will not count its words; I will write it once, in the answer.\n\n")


def post(body, timeout=1800):
    req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode("utf-8", "replace")[:500]}


def words(t):
    return len(re.findall(r"\b[\w'-]+\b", t or ""))


def show(tag, code, out, t0):
    ch = (out.get("choices") or [{}])[0]
    m = ch.get("message") or {}
    tc = m.get("tool_calls") or []
    content = m.get("content") or ""
    arg = ""
    if tc:
        try:
            arg = json.loads(tc[0]["function"]["arguments"]).get("content", "")
        except Exception as e:   # noqa: BLE001
            arg = "ARGS-PARSE-FAIL %r" % e
    r = {"tag": tag, "http": code, "s": round(time.time() - t0, 1), "finish": ch.get("finish_reason"),
         "reasoning_words": words(m.get("reasoning_content")), "content_words": words(content),
         "tool_calls": [c["function"]["name"] for c in tc], "tool_content_words": words(arg),
         "content_head": content[:160], "reasoning_head": (m.get("reasoning_content") or "")[:200],
         "error": out.get("error")}
    print(json.dumps(r), flush=True)
    open(OUT, "a", encoding="utf-8").write(json.dumps(dict(r, content=content, reasoning=m.get("reasoning_content"), tool_arg=arg)) + "\n")


U1 = {"role": "user", "content": "Write a 1,500-word short story about a lighthouse keeper who receives letters from someone who does not exist yet."}
U2 = {"role": "user", "content": "Write a 1,500-word short story about a lighthouse keeper who receives letters from someone who does not exist yet, and save it to story.md."}
for tag, body in [
    ("F1a content-continue, chat", {"messages": [SYS, U1, {"role": "assistant", "reasoning_content": PLAN, "content": ""}],
                                    "continue_final_message": "content", "add_generation_prompt": False, "seed": 1}),
    ("F1b content-continue, write_file", {"messages": [SYS, U2, {"role": "assistant", "reasoning_content": PLAN, "content": ""}],
                                          "continue_final_message": "content", "add_generation_prompt": False, "tools": [WF], "seed": 1}),
    ("F2a reasoning-continue (steer), chat", {"messages": [SYS, U1, {"role": "assistant", "reasoning_content": STEER, "content": ""}],
                                              "continue_final_message": "reasoning_content", "add_generation_prompt": False, "seed": 1}),
    ("F2b reasoning-continue (steer), write_file", {"messages": [SYS, U2, {"role": "assistant", "reasoning_content": STEER, "content": ""}],
                                                    "continue_final_message": "reasoning_content", "add_generation_prompt": False, "tools": [WF], "seed": 1}),
]:
    t0 = time.time()
    code, out = post(body)
    show(tag, code, out, t0)
