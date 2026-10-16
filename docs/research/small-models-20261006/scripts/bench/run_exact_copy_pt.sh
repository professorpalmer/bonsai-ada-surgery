#!/usr/bin/env bash
# Exact-copy edit probe at presence 1.5 with the presence penalty only inside the thinking (Plan S3, S3b decision).
# Engine: BONSAI_SMALL_BIN (an engine with --presence-thinking-only; the request field presence_thinking_only).
#   BONSAI_SMALL_BIN=<bin> bash bench/run_exact_copy_pt.sh [LIMIT] [models...]  -> results/<model>/exact_copy_pt/
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; LOG="$ROOT/receipts/exact_copy_pt.log"; KEY="$ROOT/artifacts/api_key.txt"
LIMIT=${1:-0}; shift; MODELS=("$@"); [ ${#MODELS[@]} -eq 0 ] && MODELS=(9B 4B 2B)
: "${BONSAI_SMALL_BIN:?set BONSAI_SMALL_BIN to the engine bin}"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() { powershell -NoProfile -ExecutionPolicy Bypass -File ../bonsai-2-27b-serve/bench/stop_serve.ps1 >/dev/null 2>&1; }
"$BONSAI_SMALL_BIN/llama-server.exe" --help 2>&1 | grep -q "presence-thinking-only" || { say "engine in $BONSAI_SMALL_BIN has no --presence-thinking-only"; exit 1; }
for M in "${MODELS[@]}"; do
  MODEL="C:/Users/<user>/models/bonsai2-small/$M/Ternary-Bonsai-2-$M-PTQ1_0.gguf"
  stop_all; rm -f logs/launcher.log
  env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LAYER=0 BONSAI_PRESENCE=0.0 BONSAI_SMALL_BIN="$BONSAI_SMALL_BIN" \
    BONSAI_LOG_FILE="logs/server_exact_pt_$M.log" BONSAI_STDERR_FILE="logs/server_exact_pt_$M.stderr" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-small.ps1' -RedirectStandardOutput '$ROOT\logs\launcher.log'"
  ok=0; for i in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
  say "$M: health=$ok (bin $BONSAI_SMALL_BIN)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/exact_copy_probe.py --base http://127.0.0.1:8080 --key-file "$KEY" --out "results/$M/exact_copy_pt" \
    --limit "$LIMIT" --presence 1.5 --presence-think-only 2>&1 | tail -1 | sed "s/^/$M: /" | tee -a "$LOG"
done
stop_all
say "=== exact-copy pt done"
