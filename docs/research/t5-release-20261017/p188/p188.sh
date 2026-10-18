#!/usr/bin/env bash
# P188: null test for the T5 hold: window off, GGML_CUDA_FA_CHUNK=16384 (#138 comment 6245027983).
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=$SP/p188.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
K="$(cygpath -m $TEMP/r-t5/artifacts/api_key.txt)"
say "=== P188: $("$TEMP/r-t5/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); GGML_CUDA_FA_CHUNK=16384, window off"
start() { local NAME=$1; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 GGML_CUDA_FA_CHUNK=16384 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/r-t5)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\p188_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\p188_$NAME.server.log'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME: health=$ok; $(grep -o 'deeper in chunks of [0-9]*' logs/p188_$NAME.launcher.log | head -1); window: $(grep -c 'LLAMA_PREFILL_WINDOW=' logs/p188_$NAME.launcher.log); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"; [ $ok = 1 ]; }
for set in code prose; do
  start $set && PYTHONUTF8=1 python "$SP/p170/p170_drive.py" --set $set --arm dense --key-file "$K" --out "$(cygpath -m $SP)/p188_$set.jsonl" < /dev/null 2>&1 | tail -1 | cut -c1-160 | sed "s/^/p188 $set /" | tee -a "$LOG"
  say "  CUDA errors $(grep -c 'CUDA error' logs/p188_$set.server.log)"
done
stopall
say "=== P188 done"
