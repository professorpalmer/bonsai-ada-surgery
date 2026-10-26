#!/usr/bin/env bash
# turing-proxy-20261026 T2: GGML_CUDA_FA_F16_V_ROWS = 16 / 32 / 64 (engine research/tp-f16-vprefetch) against tp-p4, Turing front end on the RTX 4070.
SP=$(dirname "$(realpath "$0")"); P4B=<projects>/build-tp-p4/bin
MODEL="$(cygpath -w <projects>/bonsai-2-27b-serve/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)"
TXT="$(cygpath -w <projects>/bonsai-2-27b-serve/artifacts/eval/wiki.test.raw)"
LOG=$SP/tp.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
bin() { [ $1 = p4 ] && echo $P4B || echo <projects>/build-tpv${1#v}/bin; }
say "T2 engines: $("$(bin v16)/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
for v in v16 v32 v64; do
  "$(bin $v)/test-backend-ops.exe" -o FLASH_ATTN_EXT > "$SP/t2_tbo_$v.out" 2>&1
  say "T2 $v FLASH_ATTN_EXT: $(grep -E '[0-9]+/[0-9]+ tests passed' "$SP/t2_tbo_$v.out" | tail -1); FAIL lines $(grep -c FAIL "$SP/t2_tbo_$v.out")"
done
export GGML_CUDA_BATCH_INVARIANT=1
# f16 cache (every batch reads F16 tiles) and q3_0 with the f16 prefill copy (the 8 GB prefill)
for kv in "f16 0" "q3_0 32768"; do set -- $kv; t=$1; f=$2; export GGML_CUDA_FA_CHUNK=$f
  for cell in "8192 2 512" "2048 1 8"; do set -- $cell; c=$1; n=$2; ub=$3
    GGML_CUDA_FA_PREFILL_F16=$f "$P4B/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c $c --chunks $n -ngl 99 -fa on -ctk $t -ctv $t -b $c -ub $ub \
      --kl-divergence-base "$(cygpath -w "$SP/kl_ref.bin")" > "$SP/t2_${t}_${c}_${ub}_p4.out" 2>&1
    for v in v16 v32 v64; do
      GGML_CUDA_FA_PREFILL_F16=$f "$(bin $v)/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c $c --chunks $n -ngl 99 -fa on -ctk $t -ctv $t -b $c -ub $ub \
        --kl-divergence-base "$(cygpath -w "$SP/kl_$v.bin")" > "$SP/t2_${t}_${c}_${ub}_$v.out" 2>&1
      cmp -s "$SP/kl_ref.bin" "$SP/kl_$v.bin" && r=identical || r=DIFFER
      say "T2 identity $v $t f16copy=$f ctx $c ub $ub: $r ($(grep -o 'PPL = [0-9.]*' "$SP/t2_${t}_${c}_${ub}_$v.out" | tail -1); ref $(grep -o 'PPL = [0-9.]*' "$SP/t2_${t}_${c}_${ub}_p4.out" | tail -1))"
      rm -f "$SP/kl_$v.bin"
    done
    rm -f "$SP/kl_ref.bin"
  done
done
run() { "$1/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk $3 -ctv $3 -o jsonl "${@:4}" 2>"$SP/$2.err" > "$SP/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d g %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['n_gen'], e['avg_ts'], e['stddev_ts']))" "$SP/$2.jsonl" | tr '\n' ';'; }
for rep in 1 2; do for v in p4 v16 v32 v64; do
  say "T2 speed r$rep $v q3_0 pp512 f16copy: $(GGML_CUDA_FA_PREFILL_F16=32768 GGML_CUDA_FA_CHUNK=32768 run "$(bin $v)" t2_pp_q3_0_${v}_r$rep q3_0 -p 512 -n 0 -r 3 -d 8192,32768)"
done; done
say "T2 done"
