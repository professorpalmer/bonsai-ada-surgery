#!/usr/bin/env bash
# Dose ladder (plan G1) on the ternary files: serve recipe (as the humaneval_serve_medium arm), layer off.
#   bash bench/run_dose_ladder.sh [sizes...]  -> results/<size>/dose_ladder/, receipts/dose_ladder.log
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; LOG="$ROOT/receipts/dose_ladder.log"; KEY="$ROOT/artifacts/api_key.txt"
SIZES=("$@"); [ ${#SIZES[@]} -eq 0 ] && SIZES=(9B 4B 2B)
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() {
  powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\<user>\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bonsai-2-small-serve\layer\bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  sleep 3
}
for S in "${SIZES[@]}"; do
  MODEL="C:/Users/<user>/models/bonsai2-small/$S/Ternary-Bonsai-2-$S-PTQ1_0.gguf"
  stop_all; rm -f logs/launcher.log
  env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LAYER=0 BONSAI_PRESENCE=0.0 BONSAI_LOG_FILE="logs/server_ladder_$S.log" BONSAI_STDERR_FILE="logs/server_ladder_$S.stderr" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-small.ps1' -RedirectStandardOutput '$ROOT\logs\launcher.log'"
  ok=0; for i in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
  say "$S: health=$ok $(grep '^listen' logs/launcher.log | cut -c1-100)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/dose_ladder.py --base http://127.0.0.1:8080 --key-file "$KEY" --arm-dir "results/$S/humaneval_serve_medium" --out "results/$S/dose_ladder" --max-fail 30 2>&1 | grep -E "^failed|^recovered" | sed "s/^/$S: /" | tee -a "$LOG"
done
stop_all
say "=== dose ladder done"
