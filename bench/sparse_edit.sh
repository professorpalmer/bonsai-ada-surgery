#!/usr/bin/env bash
# Sparse fast path: do cached page bounds follow deep prompt edits? Two arms on the same engine, both with
# GGML_CUDA_FA_SPARSE_CHECK=1 (logs attention ops whose cached bounds are stale): writes tracked (the fix) and
# GGML_CUDA_FA_SPARSE_NOTRACK=1 (the old behaviour). bench/sparse_edit.py per arm. 12 GB recipe, layer off, RAM guard on.
#   bash bench/sparse_edit.sh <root with the prototype engine>   -> receipts/sparse_edit.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"
LOG=receipts/sparse_edit.log; SP=${SPARSE:-8192,256,1024}; DEPTH=${DEPTH:-160000}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
BASE="GGML_CUDA_DISABLE_GRAPHS=1 LLAMA_ARG_KQ_MASK_PACKED=0 GGML_CUDA_FA_SPARSE=$SP GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9 GGML_CUDA_FA_SPARSE_CHECK=1"
say "=== sparse edit: depth $DEPTH, sparse $SP, root $ROOT"
for A in "track|" "notrack|GGML_CUDA_FA_SPARSE_NOTRACK=1"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  SLOG="$REPO\\logs\\spedit_$NAME.server.log"
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $BASE $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\spedit_$NAME.launcher.log' -RedirectStandardError '$SLOG'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME: health=$ok"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/sparse_edit.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --log "logs/spedit_$NAME.server.log" \
      --depth $DEPTH --tag $NAME 2>&1 | tee -a "$LOG"
  grep -m3 "CHECK" "logs/spedit_$NAME.server.log" | cut -c1-200 | tee -a "$LOG"
done
say "=== done"
