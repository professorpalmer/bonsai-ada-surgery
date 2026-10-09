"""Issue #7 (2026-10-09): is a long session past the VRAM line slower than a fresh server at the same context? Here it
was not (46.5k, line pinned at 16k: 30.4 against 31.3 ms per step, receipts/frag_ab.log). The slowdown in the issue
came from a lower VRAM line at that start (105k against 243k after the restart: other programs held 2.3 GB).
Simulates one growing chat against a running server: each turn appends a ~TURN-token user message and the model's
answer, so the server reuses the prefix; at --change-at the tool list changes (the prompt diverges near the start and
the server reads it again, as when a client enables MCP tools). Prints the context, decode tok/s, draft acceptance and
ms per draft step for each turn. With --replay-last it sends only the last request again (use it on a fresh server for
the comparison).
    python bench/frag_session.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --target 45000 --out receipts/frag_session.jsonl --tag long
    python bench/frag_session.py ... --replay-last --tag fresh
"""
import argparse, json, os, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from quick_tps import _headers  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", required=True)
ap.add_argument("--target", type=int, default=45000, help="stop when the context passes this many tokens")
ap.add_argument("--turn", type=int, default=2500, help="approximate tokens of each user message")
ap.add_argument("--answer", type=int, default=300, help="max tokens of each answer")
ap.add_argument("--change-at", type=int, default=12000, help="change the tool list when the context passes this")
ap.add_argument("--state", default="logs/frag_session_state.json", help="where the last request is kept for --replay-last")
ap.add_argument("--replay-last", action="store_true")
ap.add_argument("--tag", default="")
ap.add_argument("--out", default="receipts/frag_session.jsonl")
a = ap.parse_args()
key = open(a.key_file).read().strip()

TOOL = lambda n: {"type": "function", "function": {"name": n, "description": f"Tool {n}: read or change records.",
                  "parameters": {"type": "object", "properties": {"q": {"type": "string"}}, "required": ["q"]}}}
TOOLS_A = [TOOL(f"fs_{i}") for i in range(6)]
TOOLS_B = TOOLS_A + [TOOL(f"github_{i}") for i in range(20)]
WORDS = ["ledger", "harbor", "copper", "signal", "orchard", "granite", "lantern", "meadow", "falcon", "cipher", "violet", "river"]


def user_msg(turn):
    n = max(1, a.turn // 22)
    body = " ".join(f"Log {turn}-{i}: the {WORDS[(i + turn) % 12]} job wrote {(i * 31 + turn) % 997} rows to table {i % 17}." for i in range(n))
    return body + f"\n\nTurn {turn}: summarize the new log lines above in three sentences, then list two table numbers."


def ask(messages, tools):
    body = {"messages": messages, "tools": tools, "max_tokens": a.answer, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=_headers(key))
    r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
    t = r.get("timings") or {}
    acc = (t.get("draft_n_accepted") or 0) / t["draft_n"] if t.get("draft_n") else 0
    mlen = 1 + 2 * acc                                       # MTP draft of 2
    tps = t.get("predicted_per_second") or 0
    return r, {"prompt_n": t.get("prompt_n"), "cached": t.get("cache_n"), "gen": t.get("predicted_n"), "tps": round(tps, 1),
               "acceptance": round(acc, 3), "ms_step": round(1000 / tps * mlen, 1) if tps else None}


def log(rec):
    print(json.dumps(rec), flush=True)
    with open(a.out, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


if a.replay_last:
    st = json.load(open(a.state, encoding="utf-8"))
    _, m = ask(st["messages"], st["tools"])
    log(dict(tag=a.tag, turn="replay", ctx=st["ctx"], **m))
    sys.exit(0)

messages = [{"role": "system", "content": "You are a careful assistant for log reviews."}]
tools, ctx, turn = TOOLS_A, 0, 0
while ctx < a.target:
    turn += 1
    if tools is TOOLS_A and ctx >= a.change_at:
        tools = TOOLS_B
        log({"tag": a.tag, "turn": turn, "event": "tool list changed (6 -> 26 tools)"})
    messages.append({"role": "user", "content": user_msg(turn)})
    r, m = ask(messages, tools)
    msg = r["choices"][0]["message"]
    messages.append({"role": "assistant", "content": msg.get("content") or ""})
    ctx = (r.get("usage") or {}).get("total_tokens") or ctx
    log(dict(tag=a.tag, turn=turn, ctx=ctx, **m))
json.dump({"messages": messages[:-1], "tools": tools, "ctx": ctx}, open(a.state, "w", encoding="utf-8"))
