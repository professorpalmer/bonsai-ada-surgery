#!/usr/bin/env bash
# Exact-copy edit probe on the ternary files and their Q4_K_M teachers (plan S2b). Serve recipe, layer off.
#   bash bench/run_exact_copy.sh [LIMIT] [models...]  -> results/<model>/exact_copy/, receipts/exact_copy.log
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; LOG="$ROOT/receipts/exact_copy.log"; KEY="$ROOT/artifacts/api_key.txt"
LIMIT=${1:-0}; shift; MODELS=("$@"); [ ${#MODELS[@]} -eq 0 ] && MODELS=(9B 9B-base 4B 4B-base 2B 2B-base)
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() {
  powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\<user>\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bonsai-2-small-serve\layer\bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  sleep 3
}
for M in "${MODELS[@]}"; do
  case $M in
    *-base) S=${M%-base}; MODEL="C:/Users/<user>/models/qwen35-base/Qwen3.5-$S-Q4_K_M.gguf" ;;
    *) MODEL="C:/Users/<user>/models/bonsai2-small/$M/Ternary-Bonsai-2-$M-PTQ1_0.gguf" ;;
  esac
  stop_all; rm -f logs/launcher.log
  env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LAYER=0 BONSAI_PRESENCE=0.0 BONSAI_LOG_FILE="logs/server_exact_$M.log" BONSAI_STDERR_FILE="logs/server_exact_$M.stderr" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-small.ps1' -RedirectStandardOutput '$ROOT\logs\launcher.log'"
  ok=0; for i in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
  say "$M: health=$ok"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/exact_copy_probe.py --base http://127.0.0.1:8080 --key-file "$KEY" --out "results/$M/exact_copy" --limit "$LIMIT" 2>&1 | tail -1 | sed "s/^/$M: /" | tee -a "$LOG"
done
stop_all
say "=== exact-copy done"
