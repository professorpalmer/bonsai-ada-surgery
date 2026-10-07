"""Force-close report and per-request budget cap (Marionette hand-off 2026-10-07, items 1 and 3).

Against a server started with --reasoning-budget B, --reasoning-max-tokens-floor B+4096 and -n B+4096 (the launcher's
rule), checks:
  1. a request whose thinking hits a small per-request budget reports timings.reasoning_budget_exhausted = true,
     timings.reasoning_n and usage.completion_tokens_details.reasoning_tokens (non-streaming and streaming);
  2. a request that ends its thinking by itself reports exhausted = false;
  3. a request with a per-request budget above the server's and no max_tokens is not cut at the server's -n
     (the server log shows "no output cap; n_predict set to ...").

  python bench/budget_report_probe.py --base http://127.0.0.1:8899 [--key-file artifacts/api_key.txt]
"""
import argparse, json, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--base", default="http://127.0.0.1:8899")
ap.add_argument("--key-file")
ap.add_argument("--big-budget", type=int, default=40960)
a = ap.parse_args()
key = open(a.key_file).read().strip() if a.key_file else None
H = {"Content-Type": "application/json", **({"Authorization": "Bearer " + key} if key else {})}


def post(body, stream=False):
    req = urllib.request.Request(a.base.rstrip("/") + "/v1/chat/completions", data=json.dumps(body).encode(), headers=H)
    r = urllib.request.urlopen(req, timeout=3600)
    if not stream:
        return json.loads(r.read())
    last_t, last_u, fin = None, None, None
    for raw in r:
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data: ") or line == "data: [DONE]":
            continue
        d = json.loads(line[6:])
        last_t = d.get("timings") or last_t
        last_u = d.get("usage") or last_u
        for c in d.get("choices") or []:
            fin = c.get("finish_reason") or fin
    return {"timings": last_t, "usage": last_u, "choices": [{"finish_reason": fin, "message": {}}]}


def show(name, r):
    t, u = r.get("timings") or {}, r.get("usage") or {}
    print(f"{name:<34} finish={r['choices'][0].get('finish_reason')!s:<7} completion={u.get('completion_tokens')} "
          f"reasoning_n={t.get('reasoning_n')} exhausted={t.get('reasoning_budget_exhausted')} "
          f"usage.reasoning_tokens={(u.get('completion_tokens_details') or {}).get('reasoning_tokens')}")
    return t, u


HARD = "Prove that there are infinitely many primes of the form 4k+3. Be thorough and check every step."
EASY = "What is 2+2? Answer with one number."
ok = True
t, u = show("1. budget 64, non-streaming", post({"messages": [{"role": "user", "content": HARD}], "reasoning_budget_tokens": 64, "max_tokens": 600}))
ok &= t.get("reasoning_budget_exhausted") is True and (u.get("completion_tokens_details") or {}).get("reasoning_tokens", 0) >= 64
t, u = show("1b. budget 64, streaming", post({"messages": [{"role": "user", "content": HARD}], "reasoning_budget_tokens": 64, "max_tokens": 600,
                                            "stream": True, "stream_options": {"include_usage": True}}, stream=True))
ok &= t.get("reasoning_budget_exhausted") is True
t, u = show("2. easy, server budget", post({"messages": [{"role": "user", "content": EASY}], "max_tokens": 4000}))
ok &= t.get("reasoning_budget_exhausted") is False
r = post({"messages": [{"role": "user", "content": EASY}], "reasoning_budget_tokens": a.big_budget})
t, u = show(f"3. budget {a.big_budget}, no max_tokens", r)
ok &= r["choices"][0].get("finish_reason") == "stop"
print("PASS" if ok else "FAIL")
