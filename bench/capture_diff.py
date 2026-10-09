"""Where does a client's request differ from its previous request? Prints no prompt text, so the output is safe to
paste into an issue. For each chat request in a capture (bench/capture_proxy.py), compared with the chat request
before it: the number of messages, the first message that differs, its role, and which fields of it differ
(content, reasoning_content, tool_calls, ...), with their lengths before and after. Also: the tool list and the
settings changed or not.

    python bench/capture_diff.py logs/pi_requests.jsonl
    python bench/capture_diff.py logs/pi_requests.jsonl --last 4
"""
import argparse, json


def fields(m):
    out = {}
    for k, v in (m or {}).items():
        s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False, sort_keys=True)
        out[k] = s
    return out


def describe(i, a, b):
    fa, fb = fields(a), fields(b)
    diff = []
    for k in sorted(set(fa) | set(fb)):
        if fa.get(k) != fb.get(k):
            la, lb = len(fa[k]) if k in fa else None, len(fb[k]) if k in fb else None
            n = 0
            if la is not None and lb is not None:
                while n < min(la, lb) and fa[k][n] == fb[k][n]:
                    n += 1
            diff.append(f"{k}: {la} -> {lb} chars" + (f", same for the first {n}" if la is not None and lb is not None else ""))
    return f"first different message: #{i} (role {(a or b or {}).get('role')}): " + "; ".join(diff)


ap = argparse.ArgumentParser()
ap.add_argument("capture")
ap.add_argument("--last", type=int, default=0, help="only the last N chat requests")
a = ap.parse_args()
reqs = []
for line in open(a.capture, encoding="utf-8"):
    rec = json.loads(line)
    body = rec.get("body")
    if isinstance(body, dict) and isinstance(body.get("messages"), list):
        reqs.append((rec.get("t"), body))
if a.last:
    reqs = reqs[-(a.last + 1):]
for (t0, prev), (t1, cur) in zip(reqs, reqs[1:]):
    pm, cm = prev["messages"], cur["messages"]
    line = f"{t1}: messages {len(pm)} -> {len(cm)}"
    i = 0
    while i < min(len(pm), len(cm)) and pm[i] == cm[i]:
        i += 1
    if i == len(pm) and len(cm) >= len(pm):
        line += f"; previous request kept whole, {len(cm) - len(pm)} message(s) added"
    else:
        line += "; " + describe(i, pm[i] if i < len(pm) else None, cm[i] if i < len(cm) else None)
        roles = [m.get("role") for m in pm[i:]]
        line += f"; previous request had {len(pm) - i} message(s) from there on (roles: {', '.join(r or '?' for r in roles[:12])}{', ...' if len(roles) > 12 else ''})"
    if prev.get("tools") != cur.get("tools"):
        line += "; TOOL LIST CHANGED"
    other = {k for k in set(prev) | set(cur) if k not in ("messages", "tools") and prev.get(k) != cur.get(k)}
    if other:
        line += f"; settings changed: {', '.join(sorted(other))}"
    print(line)
