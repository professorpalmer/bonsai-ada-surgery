#!/usr/bin/env bash
# Plan S2 control: the Qwen3.5-<size> Q4_K_M base (the "teacher" class) on the same engine, flags and plan as the
# ternary files. Arms raw and serve only; HumanEval off + medium (loops = finish_reason length), tool calls on the
# serve arm, the paired suite raw vs layer on the serve arm.
#   bench/battery_teacher.sh 9B   -> results/9B-base/..., receipts/9B-base_battery.log
cd "$(dirname "$0")/.." || exit 1
export BONSAI_EXAMPLE_CHECK=0   # the S1/S2b batteries compare with runs made before the example check existed
ROOT="$(pwd -W 2>/dev/null || pwd)"; SIZE=${1:-9B}
MODEL="C:\\Users\\<user>\\models\\qwen35-base\\Qwen3.5-$SIZE-Q4_K_M.gguf"
LOG="$ROOT/receipts/${SIZE}-base_battery.log"; OUT="$ROOT/results/$SIZE-base"; mkdir -p "$OUT" "$ROOT/receipts" "$ROOT/logs"
# S2b (2026-10-07 19:10): thinking-on arms on the first MED_LIMIT problems (default 40); the 9B teacher ran to the
# 24,576 cap on 3 of its first 5 problems (~5 min each), so the full 164 cost ~16 h per arm. Thinking off stays 164.
MED_LIMIT=${MED_LIMIT:-40}
INNER=http://127.0.0.1:18080; LAYER=http://127.0.0.1:8080; KEY="$ROOT/artifacts/api_key.txt"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() {
  powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\<user>\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bonsai-2-small-serve\layer\bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  sleep 3
}
start_arm() { # LABEL "ENV ASSIGNMENTS"
  local label=$1 envs=$2
  stop_all; rm -f "$ROOT/logs/launcher.log"
  env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LOG_FILE="logs/server_${SIZE}base_$label.log" BONSAI_STDERR_FILE="logs/server_${SIZE}base_$label.stderr" $envs \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-small.ps1' -RedirectStandardOutput '$ROOT\\logs\\launcher.log'"
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
say "=== battery $SIZE-base Q4_K_M start; engine $(cd ../bonsai-2-27b-serve && bin/llama-server.exe --version 2>&1 | head -1 | cut -c1-60)"
start_arm raw "BONSAI_HARNESS_PROOF=0 BONSAI_THINK_BUDGET=-1 BONSAI_LAYER=0 BONSAI_PRESENCE=0.0" && { he raw off; he raw medium --max-tokens 24576 --limit $MED_LIMIT; }
start_arm serve "" && {
  he serve off; he serve medium --max-tokens 24576 --limit $MED_LIMIT
  KEYVAL=$(tr -d '\r\n' < "$KEY")
  say "tool-call stress (serve, inner):"; PYTHONUTF8=1 python bench/toolcall_stress.py --base "$INNER" --key "$KEYVAL" --n 3 --out "$OUT/toolcall_stress.json" 2>&1 | tail -3 | tee -a "$LOG"
  say "suite: raw (inner) vs layer (:8080), frozen plan, same seeds"
  PYTHONUTF8=1 python suite/run_suite.py --base "$INNER" --base-b "$LAYER" --key-file "$KEY" --model bonsai-2-small --out "$OUT/suite" --label-a raw --label-b layer 2>&1 | tail -14 | tee -a "$LOG"
}
say "=== battery $SIZE-base done; serve arm left running (layer :8080, inner :18080)"
