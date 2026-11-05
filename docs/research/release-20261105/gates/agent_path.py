"""R3c: the agent path with thinking on. A grammar (tools: lazy; response_format: strict) acts while the think block is
open, after the reasoning-budget sampler; check that the end-of-generation ban leaves a valid result.
    python agent_path.py --base http://127.0.0.1:8080 --key-file <root>/artifacts/api_key.txt --out r3c-<arm>.jsonl
Greedy. Prints one line per case: finish, ok (tool call with JSON arguments that name the city / JSON content with the
schema's keys)."""
import argparse
import json
import urllib.request

TOOLS = [{"type": "function", "function": {
    "name": "get_weather", "description": "Current weather for a city.",
    "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}]
SCHEMA = {"type": "object", "properties": {"city": {"type": "string"}, "population_millions": {"type": "number"}},
          "required": ["city", "population_millions"]}


def post(base, key, body):
    req = urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=1800) as r:
        return json.loads(r.read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    cases = [
        ("tools", {"messages": [{"role": "user", "content": "What is the weather in Paris right now? Use the tool."}],
                   "tools": TOOLS, "temperature": 0}),
        ("json_schema", {"messages": [{"role": "user", "content": "Give the largest city of Japan and its population."}],
                         "response_format": {"type": "json_schema", "json_schema": {"name": "city", "schema": SCHEMA}},
                         "temperature": 0}),
    ]
    with open(a.out, "a", encoding="utf-8") as out:
        for name, body in cases:
            try:
                r = post(a.base, key, body)
                ch = r["choices"][0]
                m = ch["message"]
                ok, detail = False, ""
                if name == "tools":
                    calls = m.get("tool_calls") or []
                    if calls:
                        args = json.loads(calls[0]["function"]["arguments"])
                        ok = calls[0]["function"]["name"] == "get_weather" and "paris" in str(args.get("city", "")).lower()
                        detail = json.dumps(args)
                else:
                    obj = json.loads(m.get("content") or "")
                    ok = isinstance(obj, dict) and set(SCHEMA["required"]) <= set(obj)
                    detail = json.dumps(obj)
                row = {"case": name, "finish": ch.get("finish_reason"), "ok": ok, "detail": detail[:200],
                       "reasoning_chars": len(m.get("reasoning_content") or "")}
            except Exception as e:  # noqa: BLE001 - recorded as a failed case
                row = {"case": name, "finish": None, "ok": False, "detail": f"{type(e).__name__}: {e}"[:200]}
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
            print(json.dumps(row, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
