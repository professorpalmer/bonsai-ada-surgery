#!/usr/bin/env bash
# turing-proxy-20261026 T0a, T0b, T0c, T1: compute_75 PTX builds (tp-null = 810d93e5aa, tp-p4 = a38714c63d) on the RTX 4070.
SP=$(dirname "$(realpath "$0")"); NULLB=<projects>/build-tp-null/bin; P4B=<projects>/build-tp-p4/bin
MODEL="$(cygpath -w <projects>/bonsai-2-27b-serve/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)"
TXT="$(cygpath -w <projects>/bonsai-2-27b-serve/artifacts/eval/wiki.test.raw)"
LOG=$SP/tp.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
export CUDA_CACHE_PATH="$(cygpath -w "$TEMP/tp-jit")" CUDA_CACHE_MAXSIZE=4294967296
mkdir -p "$TEMP/tp-jit"
say "engines: null $("$NULLB/llama-perplexity.exe" --version 2>&1 | grep -o "commit [0-9a-f]*"), p4 $("$P4B/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); mem $(nvidia-smi --query-gpu=clocks.max.mem --format=csv,noheader)"

t0=$(date +%s)
"$P4B/test-backend-ops.exe" -o FLASH_ATTN_EXT > "$SP/t0a.out" 2>&1
say "T0a p4 FLASH_ATTN_EXT: $(grep -E '[0-9]+/[0-9]+ tests passed' "$SP/t0a.out" | tail -1); FAIL lines $(grep -c FAIL "$SP/t0a.out"); $(( $(date +%s) - t0 )) s (includes the first JIT)"

export GGML_CUDA_BATCH_INVARIANT=1
for kv in q3_0 q4_0; do for cell in "8192 2 512" "2048 1 1" "2048 1 4" "2048 1 8"; do
  set -- $cell; c=$1; n=$2; ub=$3
  for t in null p4; do D=$NULLB; [ $t = p4 ] && D=$P4B
    "$D/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c $c --chunks $n -ngl 99 -fa on -ctk $kv -ctv $kv -b $c -ub $ub \
      --kl-divergence-base "$(cygpath -w "$SP/kl_$t.bin")" > "$SP/t0b_${kv}_${c}_${ub}_$t.out" 2>&1
  done
  cmp -s "$SP/kl_null.bin" "$SP/kl_p4.bin" && r=identical || r=DIFFER
  say "T0b $kv ctx $c ub $ub: $r (null $(grep -o 'Final estimate: PPL = [0-9.]*' "$SP/t0b_${kv}_${c}_${ub}_null.out"); p4 $(grep -o 'PPL = [0-9.]*' "$SP/t0b_${kv}_${c}_${ub}_p4.out" | tail -1); $(stat -c %s "$SP/kl_p4.bin") bytes)"
  rm -f "$SP/kl_null.bin" "$SP/kl_p4.bin"
done; done

while [ ! -f "$SP/tpv.done" ]; do sleep 15; done; say "T2 builds done; speed runs start"
run() { "$1/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk $3 -ctv $3 -o jsonl "${@:4}" 2>"$SP/$2.err" > "$SP/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d g %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['n_gen'], e['avg_ts'], e['stddev_ts']))" "$SP/$2.jsonl" | tr '\n' ';'; }
for kv in q3_0 q4_0; do
  for f16 in 0 32768; do for t in null p4; do D=$NULLB; [ $t = p4 ] && D=$P4B
    say "T0c/T1 $kv $t pp512 f16=$f16: $(GGML_CUDA_FA_PREFILL_F16=$f16 run $D t1_pp_${kv}_f16${f16}_$t $kv -p 512 -n 0 -r 3 -d 32768)"
  done; done
  for t in null p4; do D=$NULLB; [ $t = p4 ] && D=$P4B
    say "T1 $kv $t tg128: $(GGML_CUDA_FA_PREFILL_F16=32768 run $D t1_tg_${kv}_$t $kv -p 0 -n 128 -r 3 -d 32768,65536)"
  done
done
say "tp done"
