#!/usr/bin/env bash
# turing-proxy-20261026 T0c (rerun): the first T0c never reached the f16 copy (KV 33,280 cells > GGML_CUDA_FA_PREFILL_F16=32768, no chunking).
# Now the 8 GB launcher's settings: GGML_CUDA_FA_PREFILL_F16=32768 + GGML_CUDA_FA_CHUNK=32768 (depth 8k: one f16 copy; depth 32k: chunks).
SP=$(dirname "$(realpath "$0")"); NULLB=<projects>/build-tp-null/bin; P4B=<projects>/build-tp-p4/bin
MODEL="$(cygpath -w <projects>/bonsai-2-27b-serve/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)"
LOG=$SP/tp.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
export GGML_CUDA_BATCH_INVARIANT=1
run() { "$1/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk $3 -ctv $3 -o jsonl "${@:4}" 2>"$SP/$2.err" > "$SP/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d g %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['n_gen'], e['avg_ts'], e['stddev_ts']))" "$SP/$2.jsonl" | tr '\n' ';'; }
for rep in 1 2; do for kv in q3_0 q4_0; do for mode in inplace f16; do for t in null p4; do D=$NULLB; [ $t = p4 ] && D=$P4B
  if [ $mode = f16 ]; then F=32768; C=32768; else F=0; C=0; fi
  n=t0c2_${kv}_${mode}_${t}_r$rep
  say "T0c2 r$rep $kv $t $mode: $(GGML_CUDA_FA_PREFILL_F16=$F GGML_CUDA_FA_CHUNK=$C run $D $n $kv -p 512 -n 0 -r 3 -d 8192,32768) chunk log lines $(grep -c 'GGML_CUDA_FA_CHUNK: chunks' "$SP/$n.err")"
done; done; done; done
say "T0c2 done"
