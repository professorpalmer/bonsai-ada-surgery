#!/usr/bin/env bash
# G2c (DECISIONS 2026-10-10 03:05): the check note on the 1-bit 4B only, new seeds 7-12 of the five computation tasks.
# Paired, same seeds; second layer on :8081 with --check-note in front of the same llama-server.
#   bench/run_g2c.sh [sizes...]   (default 4B)   -> results/<size>/g2c_computation/, receipts/g2c.log
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"; LOG="$ROOT/receipts/g2c.log"; KEY="$ROOT/artifacts/api_key.txt"
SIZES=("$@"); [ ${#SIZES[@]} -eq 0 ] && SIZES=(4B)
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() {
  powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\<user>\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force; Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -match 'bonsai_layer' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  sleep 3
}
say "=== G2c start; sizes ${SIZES[*]}; layer check_note default off; plan bench/plans/computation_c.json"
for S in "${SIZES[@]}"; do
  MODEL="C:\\Users\\<user>\\models\\bonsai2-small\\$S\\Ternary-Bonsai-2-$S-PTQ1_0.gguf"
  stop_all; rm -f logs/launcher.log
  env BONSAI_SMALL_MODEL="$MODEL" BONSAI_SMALL_PORT=8080 BONSAI_LOG_FILE="logs/server_g2_$S.log" BONSAI_STDERR_FILE="logs/server_g2_$S.stderr" \
    powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-small.ps1' -RedirectStandardOutput '$ROOT\\logs\\launcher.log'"
  ok=0; for i in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:18080/health 2>/dev/null | grep -q '"ok"' && curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -qi ok && { ok=1; break; }; done
  BONSAI_LAYER_KEY="$(tr -d '\r\n' < "$KEY")" powershell -NoProfile -Command "Start-Process python -WindowStyle Hidden -ArgumentList '\"$ROOT\\layer\\bonsai_layer.py\"','--host','127.0.0.1','--port','8081','--upstream','http://127.0.0.1:18080','--check-note'"
  ok2=0; for i in $(seq 1 20); do sleep 1; curl -s -m 2 http://127.0.0.1:8081/health 2>/dev/null | grep -qi ok && { ok2=1; break; }; done
  say "$S: serve health=$ok, check layer health=$ok2"
  [ $ok = 1 ] && [ $ok2 = 1 ] || { say "$S skipped"; continue; }
  PYTHONUTF8=1 python suite/run_suite.py --base http://127.0.0.1:8080 --base-b http://127.0.0.1:8081 --key-file "$KEY" --model bonsai-2-small \
    --plan bench/plans/computation_c.json --out "results/$S/g2c_computation" --label-a layer --label-b layer_check 2>&1 | tail -8 | tee -a "$LOG"
done
stop_all
say "=== G2c done"
