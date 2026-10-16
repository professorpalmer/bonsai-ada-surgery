#!/usr/bin/env bash
# Plan S1 battery for one small model. Arms (DECISIONS.md): raw, raw+pp, serve, serve+pp; the layer rides on the
# serve arm (suite raw vs layer). Each arm restarts the launcher with its flags, then: HumanEval off + medium
# (sandbox-scored; loops = finish_reason length), tool-call stress on the serve arm, the paired suite on the serve arm.
#   bench/suite_only.sh 4B [PTQ1_0]   resumes the serve-arm suite of a paused battery (writes the battery's done line)
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; SIZE=${1:-9B}; Q=${2:-PTQ1_0}
MODEL="C:\\Users\\<user>\\models\\bonsai2-small\\$SIZE\\Ternary-Bonsai-2-$SIZE-$Q.gguf"
LOG="$ROOT/receipts/${SIZE}_battery.log"; OUT="$ROOT/results/$SIZE"; mkdir -p "$OUT" "$ROOT/receipts" "$ROOT/logs"
INNER=http://127.0.0.1:18080; LAYER=http://127.0.0.1:8080; KEY="$ROOT/artifacts/api_key.txt"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() {
  powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\<user>\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bonsai-2-small-serve\layer\bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  sleep 3
}
start_arm() { # LABEL "ENV ASSIGNMENTS"
  local label=$1 envs=$2
  stop_all; rm -f "$ROOT/logs/launcher.log"
  env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LOG_FILE="logs/server_$label.log" BONSAI_STDERR_FILE="logs/server_$label.stderr" $envs \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-small.ps1' -RedirectStandardOutput '$ROOT\\logs\\launcher.log'"
  # with the layer off the server itself listens on :8080; with it on, llama-server sits behind it on :18080
  local ok=0 i; for i in $(seq 1 60); do sleep 2
    if grep -q "^layer  on" "$ROOT/logs/launcher.log" 2>/dev/null; then INNER=http://127.0.0.1:18080; else INNER=http://127.0.0.1:8080; fi
    curl -s -m 2 "$INNER/health" 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
  say "arm $label: health=$ok inner=$INNER $(grep '^listen' "$ROOT/logs/launcher.log" | cut -c1-110)"
  [ $ok = 1 ]
}
he() { # ARM-LABEL he-arm extra...
  local label=$1 arm=$2; shift 2
  PYTHONUTF8=1 python bench/humaneval_run.py --base "$INNER" --key-file "$KEY" --arm "$arm" --out "$OUT/humaneval_${label}_${arm}" "$@" 2>&1 | grep -E "^pass@1" | tee -a "$LOG"
  python - "$OUT/humaneval_${label}_${arm}/summary.json" <<'PY' | tee -a "$LOG"
import json, sys
# finish is in summary.json rows (samples.jsonl has no finish field; before 2026-10-07 this always printed 0)
rows = json.load(open(sys.argv[1], encoding="utf-8"))["rows"]
loops = sum(1 for r in rows if r.get("finish") == "length")
print(f"   loops (finish=length): {loops}/{len(rows)}")
PY
}
say "=== suite-only resume $SIZE $Q start (results.jsonl resumes; done runs are skipped)"
start_arm serve "" && {
  say "suite: raw (inner) vs layer (:8080), frozen plan, same seeds (resumed)"
  PYTHONUTF8=1 python suite/run_suite.py --base "$INNER" --base-b "$LAYER" --key-file "$KEY" --model bonsai-2-small --out "$OUT/suite" --label-a raw --label-b layer 2>&1 | tail -14 | tee -a "$LOG"
}
say "=== battery $SIZE done; serve arm left running (layer :8080, inner :18080)"
