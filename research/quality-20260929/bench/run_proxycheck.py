"""E3: identical plain client requests, direct to llama-server (:8080) vs through the interpreter proxy (:8081)."""
import argparse, json, os, re, time, urllib.request
import puzzles
from run import KEY

PORT = {"DIRECT": 18080, "PROXY": 8080}   # since 2026-10-01 the layer owns :8080 and llama-server sits on :18080


def ask(kind, seed, arm, out_dir):
    q, truth = puzzles.make(kind, seed)
    body = {"model": "bonsai-2-27b", "messages": [{"role": "user", "content": q}], "temperature": 1.0, "top_p": 0.95,
            "top_k": 20, "min_p": 0.05, "reasoning_format": "deepseek", "max_tokens": 32768, "seed": seed * 7 + 11}
    t0 = time.time()
    req = urllib.request.Request(f"http://127.0.0.1:{PORT[arm]}/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    try:
        r = json.loads(urllib.request.urlopen(req, timeout=3600).read())
    except Exception as e:
        rec = dict(kind=kind, seed=seed, arm=arm, status="infra_error", error=repr(e)[:300])
    else:
        c = r["choices"][0]["message"].get("content") or ""
        f = re.findall(r"ANSWER:\s*\**\s*(-?[\d,]+)", c)
        ans = int(f[-1].replace(",", "")) if f else None
        rec = dict(kind=kind, seed=seed, arm=arm, status="ok", truth=truth, answer=ans, correct=ans == truth,
                   tokens=(r.get("usage") or {}).get("completion_tokens"), runs=len(r.get("interpreter_trace") or []),
                   leaked_tool_calls=bool(r["choices"][0]["message"].get("tool_calls")), wall_s=round(time.time() - t0, 1))
    os.makedirs(out_dir, exist_ok=True)
    if rec.get("status") == "ok":
        rec["response"] = r   # full response (reasoning_content, content, usage, interpreter_trace) for the trace bundle
    json.dump(rec, open(os.path.join(out_dir, f"{kind}-{seed}-{arm}.json"), "w", encoding="utf-8"))
    return rec


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--plan"); ap.add_argument("--out"); a = ap.parse_args()
    for k, s, arm in json.load(open(a.plan))["order"]:
        if not os.path.exists(os.path.join(a.out, f"{k}-{s}-{arm}.json")):
            print(json.dumps(ask(k, s, arm, a.out)), flush=True)
