#!/usr/bin/env bash
# Block-sparse prefill at depth: dense vs sparse reads in prefill too (GGML_CUDA_FA_SPARSE fast path up to MAXQ queries,
# GGML_CUDA_FA_TILE_SKIP=1 so the MMA kernel skips KV tiles that are -inf for a whole query tile). 12 GB recipe with the
# VRAM line pinned at 32,768 cells (most of the prompt in the host tail, as on 8 GB), layer off, f16 mask, graphs off.
# Per arm: quick_tps at DEPTH (prefill and decode speed), code_needle (exact copies) and needle_depth (12 facts).
#   bash bench/sparse_prefill.sh <root with the engine>   -> docs/receipts/sparse_prefill.{log,jsonl}
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"
LOG=docs/receipts/sparse_prefill.log; OUT=docs/receipts/sparse_prefill.jsonl; DEPTH=${DEPTH:-160000}; SP=${SPARSE:-8192,256,1024}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1' EXIT
# GRAPHS=on keeps CUDA graphs (an engine with patch 0053 turns them off per graph past the line); PACKED=1 keeps the
# packed KQ mask (decode ops up to 31 queries get an f16 mask either way). Defaults: graphs off, f16 mask.
GR=$([ "${GRAPHS:-off}" = on ] || echo GGML_CUDA_DISABLE_GRAPHS=1); PK=$([ "${PACKED:-0}" = 1 ] || echo LLAMA_ARG_KQ_MASK_PACKED=0)
BASE="BONSAI_KV_VRAM_CELLS=32768 $PK $GR"
SPARSE_ENV="GGML_CUDA_FA_SPARSE=$SP GGML_CUDA_FA_SPARSE_FAST=1 GGML_CUDA_KV_TIER_STAGE_MIN_Q=9"
say "=== sparse prefill: depth $DEPTH, sparse $SP, graphs ${GRAPHS:-off}, packed ${PACKED:-0}, root $ROOT"
for A in "dense|" "sparse-decode|$SPARSE_ENV" "sparse-prefill|$SPARSE_ENV GGML_CUDA_FA_SPARSE_MAXQ=4096 GGML_CUDA_FA_TILE_SKIP=1"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  [[ " ${ARMS:-dense sparse-decode sparse-prefill} " == *" $NAME "* ]] || continue
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $BASE $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\spprefill_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\spprefill_$NAME.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME ($ENVS): health=$ok; $(grep '^kv' logs/spprefill_$NAME.launcher.log | cut -c1-90)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH 2>&1 | sed "s/^/$NAME /" | tee -a "$LOG"
  PYTHONUTF8=1 python bench/code_needle.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH --n ${CN:-10} --tag $NAME --out $OUT 2>&1 | tail -1 | tee -a "$LOG"
  PYTHONUTF8=1 python bench/needle_depth.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH --n 12 --tag $NAME --out $OUT 2>&1 | tail -1 | tee -a "$LOG"
  say "$NAME: $(grep -c 'GGML_CUDA_FA_SPARSE B=' logs/spprefill_$NAME.server.log) engaged lines; last: $(grep 'GGML_CUDA_FA_SPARSE B=' logs/spprefill_$NAME.server.log | tail -1 | cut -c1-160)"
done
say "=== done"
