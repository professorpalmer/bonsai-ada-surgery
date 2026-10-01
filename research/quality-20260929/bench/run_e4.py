import json, os, sys
import run
plan = json.load(open("E4-plan.json"))
for k, s, arm in plan["order"]:
    out = os.path.join("E4", arm)
    if os.path.exists(os.path.join(out, f"{k}-{s}-P0.jsonl")) and any(
            json.loads(l).get("event") == "grade" for l in open(os.path.join(out, f"{k}-{s}-P0.jsonl"), encoding="utf-8")):
        continue
    run.BASE = "http://127.0.0.1:8080" if arm == "DIRECT" else "http://127.0.0.1:8081"
    g = run.run_attempt(k, s, "P0", out)
    print(json.dumps({"kind": k, "seed": s, "arm": arm, **{x: g[x] for x in ("full_pass", "functional", "process_ok", "status", "responses", "wall_s", "completion_tokens")}}), flush=True)
