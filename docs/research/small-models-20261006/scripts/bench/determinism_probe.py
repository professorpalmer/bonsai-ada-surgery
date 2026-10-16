"""Determinism probe (DECISIONS 2026-10-06 06:xx): does the raw server give the same completion for the same request and seed?

Sends the suite's exact first MIME request (same PROFILE, tools, seed formula) to the inner server N times in three
conditions and compares the full response (reasoning_content, content, tool call arguments):
  A  cache_prompt true, back to back (what the suite does; the prompt cache is warm from the 2nd call on)
  B  cache_prompt false, back to back (every call prefills the whole prompt)
  C  cache_prompt true, after a different long request between calls (the cache holds another prefix)
Also: condition B with max_tokens 64 and temperature 0 (greedy) as the floor: that one must be identical.
Usage: python bench/determinism_probe.py [--n 3] [--base http://127.0.0.1:18080] [--effort medium]
"""
import argparse, hashlib, json, os, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "suite"))
import cases  # noqa: E402
import run_suite  # noqa: E402


def post(base, key, body, timeout=1800):
    req = urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())


def fingerprint(resp):
    m = resp["choices"][0]["message"]
    calls = [(c.get("function", {}).get("name"), c.get("function", {}).get("arguments")) for c in (m.get("tool_calls") or [])]
    blob = json.dumps({"r": m.get("reasoning_content"), "c": m.get("content"), "t": calls}, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode()).hexdigest()[:12], len(blob), resp.get("usage", {}).get("completion_tokens")


def first_divergence(a, b):
    ma, mb = a["choices"][0]["message"], b["choices"][0]["message"]
    ta = (ma.get("reasoning_content") or "") + "\n---\n" + (ma.get("content") or "")
    tb = (mb.get("reasoning_content") or "") + "\n---\n" + (mb.get("content") or "")
    i = next((k for k, (x, y) in enumerate(zip(ta, tb)) if x != y), min(len(ta), len(tb)))
    return i, len(ta), len(tb)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:18080")
    ap.add_argument("--key-file", default=os.path.join(ROOT, "artifacts", "api_key.txt"))
    ap.add_argument("--n", type=int, default=3)
    ap.add_argument("--effort", default="medium")
    ap.add_argument("--max-tokens", type=int, default=4096)
    ap.add_argument("--extra-json", default="", help="fields merged into every request (layer flags when --base is the layer)")
    ap.add_argument("--only", default="", help="comma list of condition letters to run (default all)")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    system, user, tools = cases.prompts("xfer-mime-01")   # exactly what run_suite.run_coding sends on its first turn
    msgs = [{"role": "system", "content": system}, {"role": "user", "content": user}]
    prof = dict(run_suite.PROFILE, reasoning_effort=a.effort, chat_template_kwargs={"reasoning_effort": a.effort})
    seed = 1 * 7919 + 0
    base_body = dict(prof, messages=msgs, tools=tools, tool_choice="auto", max_tokens=a.max_tokens, seed=seed, model="bonsai")
    if a.extra_json:
        base_body.update(json.loads(a.extra_json))
    only = set(a.only.replace(" ", "").split(",")) if a.only else None

    def run(label, body, between=None):
        if only is not None and label[0] not in only:
            return None
        fps, resps = [], []
        for i in range(a.n):
            if between and i > 0:
                post(a.base, key, between)
            r = post(a.base, key, body)
            resps.append(r); fps.append(fingerprint(r))
        same = len({f[0] for f in fps}) == 1
        line = f"{label:38s} {'IDENTICAL' if same else 'DIFFER   '} " + " ".join(f"{f[0]}/{f[2]}tok" for f in fps)
        if not same:
            d = first_divergence(resps[0], resps[1])
            line += f"  first divergence at char {d[0]} of {d[1]}/{d[2]}"
        print(line, flush=True)
        return same

    other = dict(prof, messages=[{"role": "user", "content": "Summarize in one sentence:\n" + " ".join(f"item{i} note{i % 13}" for i in range(1500))}],
                 max_tokens=32, seed=5, model="bonsai", cache_prompt=True)
    print(f"determinism probe: {a.base} effort={a.effort} n={a.n} max_tokens={a.max_tokens} seed={seed}")
    run("A cache_prompt=true, back to back", dict(base_body, cache_prompt=True))
    run("B cache_prompt=false, back to back", dict(base_body, cache_prompt=False))
    run("C cache_prompt=true, other prompt between", dict(base_body, cache_prompt=True), between=other)
    run("D greedy floor: temp 0, cache false, 64 tok", dict(base_body, cache_prompt=False, temperature=0.0, max_tokens=64))
    run("E greedy, cache true, other between, 64 tok", dict(base_body, cache_prompt=True, temperature=0.0, max_tokens=64), between=other)
    # F: a request that shares the system prompt but not the user message runs between the calls, as consecutive
    # suite items do; the second call then prefills only the user message, in a smaller batch than a cold run
    sys2, user2, tools2 = cases.prompts("xfer-zip-01")
    sibling = dict(prof, messages=[{"role": "system", "content": sys2}, {"role": "user", "content": user2}], tools=tools2,
                   tool_choice="auto", max_tokens=48, seed=11, model="bonsai", cache_prompt=True)
    run("F cache true, sibling prompt (same system) between", dict(base_body, cache_prompt=True), between=sibling)
    run("G greedy, cache true, sibling between, 64 tok", dict(base_body, cache_prompt=True, temperature=0.0, max_tokens=64), between=sibling)


if __name__ == "__main__":
    main()
