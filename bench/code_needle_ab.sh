#!/usr/bin/env bash
# Exact code retrieval deep in the host tail (bench/code_needle.py): dense tiered cache vs GGML_CUDA_FA_SPARSE budgets. 12 GB recipe, VRAM line pinned
# at 32,768 cells (most of a 160k prompt in the host tail), layer off, drafting on, f16 mask, CUDA graphs off in every
# arm (the emulation needs both). bench/needle_depth.py, 10 functions.
#   bash bench/needle_ab.sh <root with the emulation engine> [budgets...]   -> receipts/needle_ab.{log,jsonl}
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"; shift
LOG=receipts/code_needle_ab.log; OUT=receipts/code_needle_ab.jsonl; DEPTH=${DEPTH:-160000}
B=("$@"); [ ${#B[@]} -eq 0 ] && B=(4096 2048)
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
# RAM guard for the whole run (tools/ramguard.ps1): stops llama-server if free commit < 6 GB or free RAM < 1.5 GB
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-server -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null' EXIT
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4; }
for b in 0 "${B[@]}"; do
  NAME=$([ $b = 0 ] && echo dense || echo "sparse$b")
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=32768 LLAMA_ARG_KQ_MASK_PACKED=0 GGML_CUDA_DISABLE_GRAPHS=1 \
      GGML_CUDA_FA_SPARSE="$b,64,1024" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\needle_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\needle_$NAME.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "arm $NAME: health=$ok; $(grep '^kv' logs/codeneedle_$NAME.launcher.log | cut -c1-110)"
  [ $ok = 1 ] && PYTHONUTF8=1 python bench/code_needle.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH --n 10 --tag $NAME --out $OUT 2>&1 | tail -1 | tee -a "$LOG"
done
stop_srv
say "=== done"
