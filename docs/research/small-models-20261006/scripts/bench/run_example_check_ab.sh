#!/usr/bin/env bash
# Plan G1b: the example check, live on the 2B. Served recipe (layer on), both arms through the layer (:8080),
# HumanEval 164 at medium, greedy, max 24576. Arm A: layer defaults; arm B: + "example_check": true per request.
#   bash bench/run_example_check_ab.sh [size]   -> results/<size>/humaneval_layer_medium, humaneval_layerec_medium
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; SIZE=${1:-2B}
MODEL="C:\\Users\\<user>\\models\\bonsai2-small\\$SIZE\\Ternary-Bonsai-2-$SIZE-PTQ1_0.gguf"
LOG="$ROOT/receipts/example_check_ab.log"; OUT="$ROOT/results/$SIZE"; KEY="$ROOT/artifacts/api_key.txt"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() { powershell -NoProfile -ExecutionPolicy Bypass -File ../bonsai-2-27b-serve/bench/stop_serve.ps1 >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bonsai-2-small-serve\layer\bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1; sleep 3; }
stop_all; rm -f "$ROOT/logs/launcher.log"
env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LOG_FILE="logs/server_ecab.log" BONSAI_STDERR_FILE="logs/server_ecab.stderr" \
  powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-small.ps1' -RedirectStandardOutput '$ROOT\\logs\\launcher.log'"
ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && grep -q "^layer  on" "$ROOT/logs/launcher.log" 2>/dev/null && { ok=1; break; }; done
say "=== G1b example check A/B, $SIZE, through the layer: health=$ok $(grep '^layer' "$ROOT/logs/launcher.log" | head -1 | cut -c1-100)"
[ $ok = 1 ] || exit 1
for arm in "layer:" "layerec:{\"example_check\": true}"; do
  label=${arm%%:*}; extra=${arm#*:}
  PYTHONUTF8=1 python bench/humaneval_run.py --base http://127.0.0.1:8080 --key-file "$KEY" --arm medium --max-tokens 24576 \
    --out "$OUT/humaneval_${label}_medium" ${extra:+--extra "$extra"} 2>&1 | grep -E "^pass@1" | sed "s/^/$label: /" | tee -a "$LOG"
done
stop_all
PYTHONUTF8=1 python - "$OUT" <<'PY' | tee -a "$LOG"
import json, os, sys
o = sys.argv[1]
a = {r["task_id"]: r for r in json.load(open(os.path.join(o, "humaneval_layer_medium", "summary.json")))["rows"]}
b = {r["task_id"]: r for r in json.load(open(os.path.join(o, "humaneval_layerec_medium", "summary.json")))["rows"]}
pa = sum(r["passed"] for r in a.values()); pb = sum(r["passed"] for r in b.values())
rec = [t for t in a if not a[t]["passed"] and b[t]["passed"]]; broke = [t for t in a if a[t]["passed"] and not b[t]["passed"]]
print(f"A layer {pa}/164, B layer+example check {pb}/164, B-A {pb-pa:+d}; recovered {len(rec)} {rec}; broke {len(broke)} {broke}")
print("rule (Plan G1b): adopt for the 2B if B-A >= +3 and broke <= 1 ->", "ADOPT" if pb - pa >= 3 and len(broke) <= 1 else "stays off")
PY
say "=== G1b done"
