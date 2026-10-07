#!/usr/bin/env bash
# Release smoke test: greedy outputs of the current product bin vs a clean unzip of a new bundle, same model, the
# launcher's served recipe (262k, tiered q8_0 KV, MTP), layer off. Then the budget report probe on the new bundle.
#   bash bench/release_smoke.sh <unzipped-bundle-dir> [tag]   -> receipts/release_smoke_<tag>.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; NEW="$1"; TAG="${2:-new}"; LOG="receipts/release_smoke_$TAG.log"
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
KEY="$REPO\\artifacts\\api_key.txt"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force" >/dev/null 2>&1; sleep 5; }
run_side() { # NAME ROOT
  local name=$1 root=$2
  stop_srv
  cp "$REPO/artifacts/api_key.txt" "$root/artifacts/api_key.txt" 2>/dev/null || { mkdir -p "$root/artifacts"; cp "$REPO/artifacts/api_key.txt" "$root/artifacts/"; }
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$root\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\smoke_$name.launcher.log' -RedirectStandardError '$REPO\\logs\\smoke_$name.server.log'"
  local ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "$name: health=$ok version: $(grep -m1 -o 'build [0-9]*, commit [0-9a-f]*\|build: [0-9]* ([0-9a-f]*)' "$REPO/logs/smoke_$name.server.log")"
  [ $ok = 1 ] || return 1
  PYTHONUTF8=1 python - "$name" "$KEY" <<'PY' | tee -a "$LOG"
import json, sys, urllib.request, hashlib
name, keyf = sys.argv[1], sys.argv[2]
key = open(keyf).read().strip()
P = [("code", "Write a Python function that parses ISO 8601 durations like P3DT4H5M into seconds, with tests.", False, 256),
     ("prose", "Explain how a transistor amplifies a signal, for a curious teenager.", False, 256),
     ("think", "A train leaves at 9:40 and arrives at 13:05. How long is the trip in minutes?", True, 1200)]
out = {}
for tag, p, think, n in P:
    body = {"messages": [{"role": "user", "content": p}], "max_tokens": n, "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": think}}
    req = urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    r = json.loads(urllib.request.urlopen(req, timeout=900).read())
    m = r["choices"][0]["message"]
    text = (m.get("reasoning_content") or "") + "\n---\n" + (m.get("content") or "")
    out[tag] = text
    t = r.get("timings", {})
    print(f"  {name:<4} {tag:<6} sha {hashlib.sha256(text.encode()).hexdigest()[:16]}  tok {r['usage']['completion_tokens']:5}  "
          f"{t.get('predicted_per_second', 0):6.1f} tok/s  exhausted={t.get('reasoning_budget_exhausted')}")
json.dump(out, open(f"logs/smoke_{name}.json", "w", encoding="utf-8"), indent=1)
PY
}
say "=== release smoke $TAG: old = $REPO\\bin, new = $NEW"
run_side old "$REPO"
run_side new "$NEW" && {
  say "budget report probe (new):"
  PYTHONUTF8=1 python bench/budget_report_probe.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt 2>&1 | tee -a "$LOG"
}
stop_srv
PYTHONUTF8=1 python - <<'PY' | tee -a "$LOG"
import json
a, b = json.load(open("logs/smoke_old.json", encoding="utf-8")), json.load(open("logs/smoke_new.json", encoding="utf-8"))
for k in a:
    print(f"  {k:<6} identical: {a[k] == b.get(k)}")
print("GREEDY IDENTICAL" if a == b else "GREEDY DIFFERS")
PY
say "=== done"
