"""Product benchmark: raw llama-server (:18080 since the layer went live) vs the integrated layer (:8080: API cards + API linter + interpreter
for requests without client tools). Identical client requests in both arms; one frozen plan across task families."""
import argparse, json, os
import agent_contract, run, run_proxycheck

def one(fam, name, seed, arm, out):
    if fam == "contract":
        r = agent_contract.attempt(name, seed, "PROD" if arm == "PROD" else "RAW", os.path.join(out, "contract"))
        return dict(functional=r["functional"] is True, full=bool(r["task_success"]), tokens=r["completion_tokens"], wall_s=r["wall_s"], detail=r["reasons"])
    if fam == "single":
        r = run_proxycheck.ask(name, seed, "PROXY" if arm == "PROD" else "DIRECT", os.path.join(out, "single"))
        return dict(functional=bool(r.get("correct")), full=bool(r.get("correct")), tokens=r.get("tokens"), wall_s=r.get("wall_s"), detail=r.get("status"))
    if fam == "workspace":
        run.BASE = "http://127.0.0.1:8080" if arm == "PROD" else "http://127.0.0.1:18080"
        g = run.run_attempt(name, seed, "P0", os.path.join(out, "workspace", arm))
        return dict(functional=bool(g["functional"]), full=bool(g["full_pass"]), tokens=g["completion_tokens"], wall_s=g["wall_s"], detail=g["status"])
    raise ValueError(fam)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--plan"); ap.add_argument("--out"); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    res = os.path.join(a.out, "results.jsonl")
    done = set()
    if os.path.exists(res):
        done = {tuple(json.loads(l)["key"]) for l in open(res, encoding="utf-8")}
    for fam, name, seed, arm in json.load(open(a.plan))["order"]:
        if (fam, name, seed, arm) in done:
            continue
        try:
            r = one(fam, name, seed, arm, a.out)
        except Exception as e:
            r = dict(functional=None, full=None, tokens=None, wall_s=None, detail="infra_error: " + repr(e)[:200])
        rec = dict(key=[fam, name, seed, arm], **r)
        with open(res, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
        print(json.dumps(rec), flush=True)
