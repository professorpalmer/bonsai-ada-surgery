"""One model, raw (no layer), on the product benchmark's task list: the RAW half of a run_product plan, pointed at
whatever llama-server is on :18080. Used for other models on identical requests (teacher Qwen3.8-27B Q4_K_M, Mirai S)."""
import argparse, json, os
import agent_contract, run_proxycheck

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--plan"); ap.add_argument("--out"); ap.add_argument("--label", required=True); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    res = os.path.join(a.out, "results.jsonl")
    done = {tuple(json.loads(l)["key"]) for l in open(res, encoding="utf-8")} if os.path.exists(res) else set()
    for fam, name, seed in json.load(open(a.plan))["order"]:
        if (fam, name, seed, a.label) in done:
            continue
        try:
            if fam == "contract":
                r = agent_contract.attempt(name, seed, "RAW", os.path.join(a.out, "contract"))
                rec = dict(functional=r["functional"] is True, full=bool(r["task_success"]), tokens=r["completion_tokens"], wall_s=r["wall_s"], detail=r["reasons"])
            elif fam == "single":
                r = run_proxycheck.ask(name, seed, "DIRECT", os.path.join(a.out, "single"))
                rec = dict(functional=bool(r.get("correct")), full=bool(r.get("correct")), tokens=r.get("tokens"), wall_s=r.get("wall_s"), detail=r.get("status"))
            else:
                raise ValueError(fam)
        except Exception as e:
            rec = dict(functional=None, full=None, tokens=None, wall_s=None, detail="infra_error: " + repr(e)[:200])
        rec = dict(key=[fam, name, seed, a.label], **rec)
        with open(res, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
        print(json.dumps(rec), flush=True)
