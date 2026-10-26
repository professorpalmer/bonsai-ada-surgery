#!/usr/bin/env bash
# P230 (RTX 2060 SUPER): turing-proxy-20261026 rig questions.
#  A: with patch 0072, the in-place q3_0 read against the 8 GB launcher's f16 copy (GGML_CUDA_FA_PREFILL_F16=32768, GGML_CUDA_FA_CHUNK=32768)
#  B: GGML_CUDA_FA_F16_V_ROWS=16 / 64 (engine c19c5988d1) against the 1026 engine on the f16 copy path: logit identity and prefill speed
# Usage: bash p230.sh <p230-tools folder (unzipped)> <1026 root> <model .gguf> <out folder>
set -u
TOOLS=$1; ROOT=$2; MODEL="$(cygpath -w "$3")"; OUT=$4
mkdir -p "$OUT"; LOG=$OUT/p230.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
TXT="$(cygpath -w "$(pwd)/artifacts/eval/wiki.test.raw")"
for e in e1026 v16 v64; do cp -n "$ROOT"/bin/cu*.dll "$ROOT"/bin/nv*.dll "$TOOLS/$e/" 2>/dev/null; done
say "P230 engines: $(for e in e1026 v16 v64; do echo -n "$e $("$TOOLS/$e/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); "; done)gpu $(nvidia-smi --query-gpu=name,clocks.max.mem --format=csv,noheader)"
export GGML_CUDA_BATCH_INVARIANT=1
run() { "$TOOLS/$1/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk q3_0 -ctv q3_0 -ub 512 -o jsonl "${@:3}" 2>"$OUT/$2.err" > "$OUT/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d g %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['n_gen'], e['avg_ts'], e['stddev_ts']))" "$OUT/$2.jsonl" | tr '\n' ';'; }

# B identity first (short): q3_0 with the f16 copy (-ub 512, ctx 8192, 2 chunks) and an f16 cache (-ub 8, ctx 2048, 1 chunk)
for cell in "q3_0 32768 8192 2 512" "f16 0 2048 1 8"; do set -- $cell; t=$1; f=$2; c=$3; n=$4; ub=$5
  for e in e1026 v16 v64; do
    GGML_CUDA_FA_PREFILL_F16=$f GGML_CUDA_FA_CHUNK=$f "$TOOLS/$e/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c $c --chunks $n -ngl 99 -fa on -ctk $t -ctv $t -b $c -ub $ub \
      --kl-divergence-base "$(cygpath -w "$OUT/kl_$e.bin")" > "$OUT/b_${t}_${ub}_$e.out" 2>&1
  done
  for e in v16 v64; do cmp -s "$OUT/kl_e1026.bin" "$OUT/kl_$e.bin" && r=identical || r=DIFFER
    say "P230 B identity $e $t ctx $c ub $ub: $r ($(grep -o 'PPL = [0-9.]*' "$OUT/b_${t}_${ub}_$e.out" | tail -1); 1026 $(grep -o 'PPL = [0-9.]*' "$OUT/b_${t}_${ub}_e1026.out" | tail -1))"
  done
  rm -f "$OUT"/kl_*.bin
done

# A and B speed: pp512 at 8k and 32k, 2 rounds, cells in turns
for rep in 1 2; do
  say "P230 A r$rep e1026 in-place: $(GGML_CUDA_FA_PREFILL_F16=0 GGML_CUDA_FA_CHUNK=0 run e1026 a_inplace_r$rep -p 512 -n 0 -r 3 -d 8192,32768)"
  for e in e1026 v16 v64; do
    say "P230 A/B r$rep $e f16 copy: $(GGML_CUDA_FA_PREFILL_F16=32768 GGML_CUDA_FA_CHUNK=32768 run $e ab_copy_${e}_r$rep -p 512 -n 0 -r 3 -d 8192,32768)"
  done
done
say "P230 CUDA errors in .err files: $(cat "$OUT"/*.err "$OUT"/*.out | grep -c 'CUDA error')"
say "P230 done"
