#!/usr/bin/env bash
# Plan S3a-live: the exact-copy probe through the layer, edit repair off (er0) and on (er1), same items and seeds.
#   bash bench/run_exact_copy_er.sh [models...]  -> results/<model>/exact_copy_layer_er{0,1}/, receipts/exact_copy_er.log
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; LOG="$ROOT/receipts/exact_copy_er.log"; KEY="$ROOT/artifacts/api_key.txt"
MODELS=("$@"); [ ${#MODELS[@]} -eq 0 ] && MODELS=(2B 4B)
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() {
  powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\<user>\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bonsai-2-small-serve\layer\bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  sleep 3
}
for M in "${MODELS[@]}"; do
  MODEL="C:/Users/<user>/models/bonsai2-small/$M/Ternary-Bonsai-2-$M-PTQ1_0.gguf"
  for ER in 0 1; do
    stop_all; rm -f logs/launcher.log
    env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LAYER=1 BONSAI_EDIT_REPAIR=$ER BONSAI_PRESENCE=0.0 BONSAI_LOG_FILE="logs/server_exact_er${ER}_$M.log" BONSAI_STDERR_FILE="logs/server_exact_er${ER}_$M.stderr" \
      powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-small.ps1' -RedirectStandardOutput '$ROOT\logs\launcher.log'"
    ok=0; for i in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
    say "$M er$ER: health=$ok; $(grep '^layer' logs/launcher.log)"
    [ $ok = 1 ] || continue
    PYTHONUTF8=1 python bench/exact_copy_probe.py --base http://127.0.0.1:8080 --key-file "$KEY" --out "results/$M/exact_copy_layer_er$ER" 2>&1 | tail -1 | sed "s/^/$M er$ER: /" | tee -a "$LOG"
  done
  PYTHONUTF8=1 python bench/edit_repair_eval.py "results/$M/exact_copy_layer_er0" 2>&1 | sed "s/^/$M offline on er0: /" | tee -a "$LOG"
done
stop_all
say "=== exact-copy er done"
