#!/usr/bin/env bash
# prefill-profile-20261027: per-op GPU time over a llama-bench depth fill (GGML_CUDA_OP_TIMING=1, CUDA graphs off).
# Usage: bash prof.sh <bin folder with llama-bench> <model .gguf> <out folder> <depth> <label:ctk:prefill_f16:chunk> [...]
#   e.g. bash prof.sh bin model.gguf out 131072 q1:q4_0:0:0 q2:q3_0:32768:32768 q3:q3_0:0:0
set -u
BIN=$1; MODEL="$(cygpath -w "$2")"; OUT=$3; D=$4; shift 4
mkdir -p "$OUT"; LOG=$OUT/prof.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
say "engine $("$BIN/llama-bench.exe" --help >/dev/null 2>&1; ls "$BIN"/llama-perplexity.exe >/dev/null 2>&1 && "$BIN/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); gpu $(nvidia-smi --query-gpu=name,clocks.max.mem,memory.used --format=csv,noheader)"
for spec in "$@"; do IFS=: read -r name ctk f16 chunk <<< "$spec"
  GGML_CUDA_OP_TIMING=1 GGML_CUDA_DISABLE_GRAPHS=1 GGML_CUDA_BATCH_INVARIANT=1 GGML_CUDA_FA_PREFILL_F16=$f16 GGML_CUDA_FA_CHUNK=$chunk \
    "$BIN/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk $ctk -ctv $ctk -ub 512 -p 512 -n 0 -r 1 -d $D -v -o jsonl > "$OUT/$name.jsonl" 2> "$OUT/$name.err"
  say "$name ($ctk, f16 copy $f16, chunk $chunk, depth $D): $(grep -c 'op timing over' "$OUT/$name.err") tables; CUDA errors $(grep -c 'CUDA error' "$OUT/$name.err")"
  grep -A 30 "op timing over" "$OUT/$name.err" | grep -E "op timing|ms/graph" | head -64 | tee -a "$LOG"
done
say "prof done"
