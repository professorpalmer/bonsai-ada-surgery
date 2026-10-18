#!/usr/bin/env bash
# KL divergence of the q8_0 / q4_0 / q3_0 K/V caches against an f16 K/V cache, same bins (product 96f6e49cdc), same model
# (Ternary-Bonsai-2-27B-PTQ1_0.gguf), wikitext-2 test, flash attention on, all on the 4070 (no tier: a plain context).
# 16k x 4 chunks and 32k x 2 chunks. Answers "how much does q3_0 K/V drift" (a user question).
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; cd $B/bin || exit 1
E=$(cygpath -w $B/artifacts/eval); M=$(cygpath -w $B/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)
LOG=$B/docs/receipts/kl_q3.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
say "=== KL q3_0: $(./llama-perplexity.exe --version 2>&1 | grep -o 'commit [0-9a-f]*'); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
for cfg in "16384 4 16k" "32768 2 32k"; do
  set -- $cfg; C=$1; N=$2; T=$3
  BASE="$E\kl_base_f16kv_${T}_1018.bin"
  COMMON=(-m "$M" -f "$E\wiki.test.raw" -c $C --chunks $N -b 2048 -ub 512 -ngl 99 -fa on)
  ./llama-perplexity.exe "${COMMON[@]}" -ctk f16 -ctv f16 --kl-divergence-base "$BASE" > "$B/logs/kl_f16_$T.log" 2>&1
  say "base $T: $(grep -E 'Final estimate' $B/logs/kl_f16_$T.log | tail -1)"
  for t in q8_0 q4_0 q3_0; do
    ./llama-perplexity.exe "${COMMON[@]}" -ctk $t -ctv $t --kl-divergence --kl-divergence-base "$BASE" > "$B/logs/kl_${t}_$T.log" 2>&1
    say "$T $t: $(grep -E 'Mean PPL\(Q\)|Mean +KLD|Same top p|99.0% +KLD|Maximum KLD' $B/logs/kl_${t}_$T.log | sed 's/  */ /g' | tr '\n' ';' | cut -c1-260)"
  done
  rm -f "$(cygpath -u "$BASE")"
done
say "=== KL q3_0 done"
