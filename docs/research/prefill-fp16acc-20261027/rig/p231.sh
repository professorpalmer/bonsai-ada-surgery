#!/usr/bin/env bash
# P231 stage 1 (RTX 2060 SUPER): fp16 accumulation in the prefill K*Q step (engine e5c4e35fc1) against the 1026 engine,
# with the 8 GB launcher's f16 copy settings. docs/research/prefill-fp16acc-20261027/README.md has the gates.
# Usage: bash p231.sh <p231-tools folder (unzipped)> <1026 root> <model .gguf> <out folder>
set -u
TOOLS=$1; ROOT=$2; MODEL="$(cygpath -w "$3")"; OUT=$4
mkdir -p "$OUT"; LOG=$OUT/p231.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
TXT="$(cygpath -w "$(pwd)/artifacts/eval/wiki.test.raw")"
for e in e1026 p2; do cp -n "$ROOT"/bin/cu*.dll "$ROOT"/bin/nv*.dll "$TOOLS/$e/" 2>/dev/null; done
say "P231 engines: e1026 $("$TOOLS/e1026/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); p2 $("$TOOLS/p2/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); gpu $(nvidia-smi --query-gpu=name,clocks.max.mem,memory.used --format=csv,noheader)"
export GGML_CUDA_BATCH_INVARIANT=1 GGML_CUDA_FA_PREFILL_F16=32768 GGML_CUDA_FA_CHUNK=32768

# KL of P2 against 1026 (q3_0, the copy settings)
"$TOOLS/e1026/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c 8192 --chunks 2 -ngl 99 -fa on -ctk q3_0 -ctv q3_0 -b 8192 -ub 512 \
  --kl-divergence-base "$(cygpath -w "$OUT/kl_base.bin")" > "$OUT/kl_e1026.out" 2>&1
"$TOOLS/p2/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c 8192 --chunks 2 -ngl 99 -fa on -ctk q3_0 -ctv q3_0 -b 8192 -ub 512 \
  --kl-divergence-base "$(cygpath -w "$OUT/kl_base.bin")" --kl-divergence > "$OUT/kl_p2.out" 2>&1
say "P231 KL: $(grep -E 'Mean +KLD|Maximum KLD|Same top|Mean +PPL\(Q\)|Mean +PPL\(base\)' "$OUT/kl_p2.out" | tr -s ' ' | tr '\n' ';')"
rm -f "$OUT/kl_base.bin"

run() { "$TOOLS/$1/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk q3_0 -ctv q3_0 -ub 512 -o jsonl "${@:3}" 2>"$OUT/$2.err" > "$OUT/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['avg_ts'], e['stddev_ts']))" "$OUT/$2.jsonl" | tr '\n' ';'; }
for rep in 1 2; do for e in e1026 p2; do
  say "P231 r$rep $e pp512: $(run $e pp_${e}_r$rep -p 512 -n 0 -r 3 -d 8192,32768,65536)"
done; done
say "P231 CUDA errors: $(cat "$OUT"/*.err "$OUT"/*.out | grep -c 'CUDA error')"
say "P231 done"
