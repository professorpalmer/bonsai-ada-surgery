"""One greedy request that must call tools, with the same 107-tool list as the issue #7 probe (PROBE_MANY_TOOLS=105,
PROBE_TOOL_CHARS=976). The tool-call grammar is then active during speculative steps, so the sampler copy on each
step carries a triggered grammar. Prints the decode speed and a hash of the tool calls and text; two engines that
copy the grammar correctly give the same hash.
    PROBE_MANY_TOOLS=105 PROBE_TOOL_CHARS=976 python bench/toolcall_identity.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag base
"""
import argparse, hashlib, json, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
src = open(os.path.join(os.path.dirname(__file__), "agent_depth_probe.py"), encoding="utf-8").read()
ns = {"os": os, "json": json}
exec(src[src.index("TOOLS = "):src.index("ASKS = [")], ns)
TOOLS = ns["TOOLS"]

ap = argparse.ArgumentParser()
ap.add_argument("--base", required=True)
ap.add_argument("--key-file", required=True)
ap.add_argument("--tag", default="")
ap.add_argument("--out", default="receipts/toolcall_identity.jsonl")
a = ap.parse_args()
key = open(a.key_file).read().strip()
ask = ("Read the files src/app.py and src/db.py with the read tool, then search the github issues for 'timeout retry' "
       "with the right tool from the list. Make all three tool calls now, in one answer.")
body = {"messages": [{"role": "user", "content": ask}], "tools": TOOLS, "temperature": 0, "top_p": 1, "max_tokens": 3000,
        "seed": 7, "chat_template_kwargs": {"enable_thinking": True}}
req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
m = r["choices"][0]["message"]
calls = [{"name": c["function"]["name"], "arguments": c["function"]["arguments"]} for c in m.get("tool_calls") or []]
t = r.get("timings") or {}
rec = {"tag": a.tag, "tools": len(TOOLS), "calls": [c["name"] for c in calls], "finish": r["choices"][0].get("finish_reason"),
       "sha": hashlib.sha256(((m.get("content") or "") + json.dumps(calls, sort_keys=True)).encode()).hexdigest()[:12],
       "tps": round(t.get("predicted_per_second") or 0, 1), "n": t.get("predicted_n"),
       "acceptance": round(t["draft_n_accepted"] / t["draft_n"], 3) if t.get("draft_n") else None}
print(json.dumps(rec), flush=True)
with open(a.out, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec) + "\n")
