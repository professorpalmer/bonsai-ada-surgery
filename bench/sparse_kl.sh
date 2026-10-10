#!/usr/bin/env bash
# Sparse reading of the host tail (GGML_CUDA_FA_SPARSE emulation): KL against the dense tiered cache. Default: line at
# 2,048 cells and a 16k window (KL_LINE / KL_CTX), so every scored position (8k-16k) attends to a host tail of 6k-14k
# cells; budget B cells of it kept per query (pages of 64, the last 1024 cells always). q8_0 K/V, CUDA
# graphs off (the emulation syncs per op). Engine: %TEMP%\build-sparse (fa-chunked-prefill + 0050 + the emulation).
#   [CORPUS=pycode.raw] bash bench/sparse_kl.sh [budgets...]   -> artifacts/eval/kl_sparse_*.log, receipts/sparse_kl.log
cd "$(dirname "$0")/.." || exit 1
BIN=/tmp/build-sparse/bin; RT=/c/Users/pwall/Projects/bonsai-2-27b-serve/bin; LOG=receipts/sparse_kl.log; OUT=artifacts/eval
B=("$@"); [ ${#B[@]} -eq 0 ] && B=(8192 4096 2048)
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
CORPUS=${CORPUS:-wiki.test.raw}; TAG=${CORPUS%%.*}
COMMON=(-m models/Ternary-Bonsai-2-27B-PTQ1_0.gguf -f $OUT/$CORPUS -c ${KL_CTX:-16384} --chunks 1 -b 2048 -ub 512 -ngl 99 -fa on -ctk q8_0 -ctv q8_0 --kv-vram-cells ${KL_LINE:-2048})
export PATH="$RT:$PATH" GGML_CUDA_DISABLE_GRAPHS=1
# RAM: the KL base keeps ~ctx/2 x 248,320 x 4 B of logits (16k context: ~8 GB). 64k (~32 GB) froze the machine twice.
[ "${KL_CTX:-16384}" -gt 16384 ] && { echo "KL_CTX > 16384 needs > 8 GB of logits RAM: refused" >&2; exit 1; }
rm -f logs/ramguard.stop
powershell -NoProfile -ExecutionPolicy Bypass -File tools/ramguard.ps1 -Names llama-perplexity -StopFile logs/ramguard.stop &
GUARD=$!
trap 'touch logs/ramguard.stop; wait $GUARD 2>/dev/null' EXIT
BASE=$OUT/kl_base_line${KL_LINE:-2048}_ctx${KL_CTX:-16384}_$TAG.bin
if [ ! -f $BASE ]; then
  say "base: dense tiered cache"
  $BIN/llama-perplexity.exe "${COMMON[@]}" --kl-divergence-base $BASE > $OUT/kl_sparse_${TAG}_line${KL_LINE:-2048}_ctx${KL_CTX:-16384}_base.log 2>&1
  say "$TAG base (ctx ${KL_CTX:-16384}, line ${KL_LINE:-2048}): $(grep -a 'Final estimate' $OUT/kl_sparse_${TAG}_line${KL_LINE:-2048}_ctx${KL_CTX:-16384}_base.log)"
fi
for b in "${B[@]}"; do
  L=$OUT/kl_sparse_${TAG}_line${KL_LINE:-2048}_ctx${KL_CTX:-16384}_B$b.log
  GGML_CUDA_FA_SPARSE="$b,64,1024" $BIN/llama-perplexity.exe "${COMMON[@]}" --kl-divergence-base $BASE --kl-divergence > $L 2>&1
  say "$TAG B=$b: $(grep -a -E 'Mean +KLD|Same top|Maximum KLD|99.9% +KLD' $L | tr -s ' ' | tr '\n' ' ') | $(grep -a 'host tail kept' $L | tail -1 | grep -o 'kept.*')"
done
say "=== done"
