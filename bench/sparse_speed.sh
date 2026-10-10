#!/usr/bin/env bash
# Decode speed deep in the window with sparse host-tail reads (prototype). 12 GB recipe at 262k, layer off, drafting on.
# One server session per arm through quick_tps at DEPTHS (default 192000 250000). Arms: dense as shipped (graphs on,
# packed mask); dense with graphs off + f16 mask (the prototype's fair baseline); sparse fast B cells (page P, recent R),
# decode reading the host tail in place so only selected pages cross PCIe. RAM guard on.
#   bash bench/sparse_speed.sh <root with the prototype engine>   -> receipts/sparse_speed.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"
LOG=receipts/sparse_speed.log; DEPTHS=${DEPTHS:-192000 250000}; SP=${SPARSE:-8192,256,1024}
# every arm: lookup drafting off by default (its verify batches of 10-33 queries are outside the fast path), so decode
# is MTP only (2-query verify steps); SPEED_ENV="" keeps the launcher default
SPEED_ENV=${SPEED_ENV-BONSAI_LOOKUP=0}
# every arm: lookup drafting off by default (its verify batches of 10-33 queries are outside the fast path), so decode
# is MTP only (2-query verify steps); SPEED_ENV="" keeps the launcher default
SPEED_ENV=${SPEED_ENV-BONSAI_LOOKUP=0}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
FAIR="GGML_CUDA_DISABLE_GRAPHS=1 LLAMA_ARG_KQ_MASK_PACKED=0"
say "=== sparse speed: depths $DEPTHS, sparse $SP, all arms: $SPEED_ENV"
for A in "dense-shipped|" "dense-fair|$FAIR" "sparse|$FAIR GGML_CUDA_FA_SPARSE=$SP GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $SPEED_ENV $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\spspeed_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\spspeed_$NAME.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME ($ENVS): health=$ok; $(grep '^kv' logs/spspeed_$NAME.launcher.log | cut -c1-90)"
  [ $ok = 1 ] || continue
  for D in $DEPTHS; do
    PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $D 2>&1 | sed "s/^/$NAME /" | tee -a "$LOG"
  done
done
say "=== done"
