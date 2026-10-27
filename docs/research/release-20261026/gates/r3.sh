#!/usr/bin/env bash
# release-20261026 R3 (logit identity) and R3b (small-batch speed): the 1025 engine (zip bin/ + llama-perplexity /
# llama-bench of its build) against the release build (whose bin/ goes into the zip).
SP=$(dirname "$(realpath "$0")"); O=$TEMP/r-pkq/bin; N=<projects>/build-rel1026/bin
MODEL="$(cygpath -w <projects>/bonsai-2-27b-serve/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)"
TXT="$(cygpath -w <projects>/bonsai-2-27b-serve/artifacts/eval/wiki.test.raw)"
LOG=$SP/release_1026.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
say "R3 engines: old $("$O/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), new $("$N/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); mem $(nvidia-smi --query-gpu=clocks.max.mem --format=csv,noheader)"
export GGML_CUDA_BATCH_INVARIANT=1
for kv in q4_0 q8_0 q3_0; do for cell in "8192 2 512" "2048 1 1" "2048 1 4" "2048 1 8"; do
  set -- $cell; c=$1; n=$2; ub=$3
  for t in old new; do D=$O; [ $t = new ] && D=$N
    "$D/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c $c --chunks $n -ngl 99 -fa on -ctk $kv -ctv $kv -b $c -ub $ub \
      --kl-divergence-base "$(cygpath -w "$SP/kl_$t.bin")" > "$SP/r3_${kv}_${c}_${ub}_$t.out" 2>&1
  done
  cmp -s "$SP/kl_old.bin" "$SP/kl_new.bin" && r=identical || r=DIFFER
  say "R3 $kv ctx $c ub $ub: $r ($(grep -o 'Final estimate: PPL = [0-9.]*' "$SP/r3_${kv}_${c}_${ub}_new.out"), $(stat -c %s "$SP/kl_new.bin") bytes)"
  rm -f "$SP/kl_old.bin" "$SP/kl_new.bin"
done; done
run() { "$1/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk $3 -ctv $3 -o jsonl "${@:4}" 2>"$SP/$2.err" > "$SP/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d g %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['n_gen'], e['avg_ts'], e['stddev_ts']))" "$SP/$2.jsonl" | tr '\n' ';'; }
for kv in q8_0 q3_0 q4_0; do
  for t in old new; do D=$O; [ $t = new ] && D=$N
    say "R3b $kv $t tg128: $(run $D r3b_tg_${kv}_$t $kv -p 0 -n 128 -r 3 -d 65536,131072)"
    say "R3b $kv $t pp4: $(run $D r3b_pp4_${kv}_$t $kv -p 4 -n 0 -r 5 -d 65536)"
  done
done
say "R3 done"
