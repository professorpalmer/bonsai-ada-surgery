"""H1 mechanism probe on real A trajectories (no tool execution: only the next response is sampled and saved).

For a saved A request at step k, P0 = the bytes-equivalent messages as the Mac harness sent them; P1 = the same
messages with each earlier assistant turn's reasoning_content re-attached from the saved A responses.
Measures the next turn's reasoning length and what it does. Model code in tool calls is recorded, never run.
"""
import json
import os
import sys
import time
import urllib.request

from run import KEY, BASE

EVID = os.path.join(os.path.dirname(__file__), "..", "evidence", "evidence", "spec-ab-v1", "runs-A")


def load(case):
    d = os.path.join(EVID, case, "private")
    reqs = json.load(open(os.path.join(d, "requests.json"), encoding="utf-8"))
    resps = json.load(open(os.path.join(d, "responses.json"), encoding="utf-8"))
    return reqs, resps


def with_reasoning(msgs, resps):
    """Attach reasoning_content to assistant messages in order (the k-th assistant msg <- response step k)."""
    rc = [r["response"]["choices"][0]["message"].get("reasoning_content") or "" for r in resps]
    out, i = [], 0
    for m in msgs:
        m = dict(m)
        if m["role"] == "assistant":
            if i < len(rc) and rc[i]:
                m["reasoning_content"] = rc[i]
            i += 1
        out.append(m)
    return out


def main(case, step, arm, rep, out_dir):
    reqs, resps = load(case)
    body = dict(reqs[step - 1]["payload"])
    n_asst = sum(1 for m in body["messages"] if m["role"] == "assistant")
    if arm == "P1":
        body["messages"] = with_reasoning(body["messages"], resps[:n_asst])
    body["seed"] = 900 + rep
    body["stream"] = False
    body.pop("stream_options", None)
    t0 = time.time()
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req, timeout=1800).read().decode("utf-8"))
    m = resp["choices"][0]["message"]
    rec = {"case": case, "step": step, "arm": arm, "rep": rep, "n_prior_assistant": n_asst,
           "prompt_tokens": resp["usage"]["prompt_tokens"], "completion_tokens": resp["usage"]["completion_tokens"],
           "reasoning_chars": len(m.get("reasoning_content") or ""),
           "tool_calls": [(c["function"]["name"], len(c["function"]["arguments"])) for c in m.get("tool_calls") or []],
           "wall_s": round(time.time() - t0, 1), "response": resp}
    os.makedirs(out_dir, exist_ok=True)
    json.dump(rec, open(os.path.join(out_dir, f"{case}-s{step}-{arm}-r{rep}.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(json.dumps({k: rec[k] for k in ("case", "step", "arm", "rep", "prompt_tokens", "completion_tokens",
                                          "reasoning_chars", "tool_calls", "wall_s")}), flush=True)


if __name__ == "__main__":
    plan = json.load(open(sys.argv[1]))
    for case, step, arm, rep in plan["order"]:
        p = os.path.join(sys.argv[2], f"{case}-s{step}-{arm}-r{rep}.json")
        if os.path.exists(p):
            continue
        main(case, step, arm, rep, sys.argv[2])
