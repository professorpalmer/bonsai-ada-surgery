#!/usr/bin/env bash
# Noise floor: a second window-off run of code + prose on the release bins (#138, declared).
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=docs/receipts/t5_off2.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
K="$(cygpath -m $TEMP/r-t5/artifacts/api_key.txt)"; W=""
say "=== T5 off2: $("$TEMP/r-t5/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); $W; clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
start() { local NAME=$1; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/r-t5)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\t5off2_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\t5off2_$NAME.server.log'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME: health=$ok; env line: $(grep -o 'LLAMA_PREFILL_WINDOW=[^ ]*' logs/t5off2_$NAME.launcher.log | head -1)"; [ $ok = 1 ]; }
for set in code prose; do
  start $set && PYTHONUTF8=1 python "$SP/p170/p170_drive.py" --set $set --arm dense --key-file "$K" --out "$(cygpath -m $B/docs/receipts)/t5_off2_$set.jsonl" < /dev/null 2>&1 | tail -1 | cut -c1-160 | sed "s/^/d8 $set /" | tee -a "$LOG"
  say "  CUDA errors $(grep -c 'CUDA error' logs/t5off2_$set.server.log)"
done
stopall
say "=== T5 off2 done"
