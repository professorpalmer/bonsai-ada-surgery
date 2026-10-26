#!/usr/bin/env bash
# fa-config-20261026 C0 / C1 / C2 (docs/research/fa-config-20261026/README.md). Waits for build_cfg.cmd.
SP=$(dirname "$(realpath "$0")"); P=<projects>
until grep -q "^=== done" "$SP/build_cfg.log" 2>/dev/null; do sleep 20; done
bin() { [ $1 = base ] && echo $P/build-rel1026/bin || echo $P/build-cfg$1/bin; }
for v in E B C; do cp $P/build-rel1026/bin/cu*.dll $P/build-rel1026/bin/nv*.dll "$(bin $v)/"; done
MODEL="$(cygpath -w $P/bonsai-2-27b-serve/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)"
TXT="$(cygpath -w $P/bonsai-2-27b-serve/artifacts/eval/wiki.test.raw)"
LOG=$SP/cfg.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
say "engines: $(for v in base E B C; do echo -n "$v $("$(bin $v)/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); "; done)mem $(nvidia-smi --query-gpu=clocks.max.mem --format=csv,noheader)"
for v in E B C; do
  "$(bin $v)/test-backend-ops.exe" -o FLASH_ATTN_EXT > "$SP/c0_$v.out" 2>&1
  say "C0 $v: $(grep -E '[0-9]+/[0-9]+ tests passed' "$SP/c0_$v.out" | tail -1); FAIL lines $(grep -c FAIL "$SP/c0_$v.out")"
done
export GGML_CUDA_BATCH_INVARIANT=1
PPL() { "$(bin $1)/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c 8192 --chunks 2 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 8192 -ub 512 "${@:2}"; }
PPL base --kl-divergence-base "$(cygpath -w "$SP/kl_base.bin")" > "$SP/c2_base.out" 2>&1
PPL E --kl-divergence-base "$(cygpath -w "$SP/kl_E.bin")" > "$SP/c2_E.out" 2>&1
cmp -s "$SP/kl_base.bin" "$SP/kl_E.bin" && r=identical || r=DIFFER; rm -f "$SP/kl_E.bin"
say "C2 E: $r"
for v in B C; do
  PPL $v --kl-divergence-base "$(cygpath -w "$SP/kl_base.bin")" --kl-divergence > "$SP/c2_$v.out" 2>&1
  say "C2 $v: $(grep -E 'Mean +KLD|Maximum KLD|Same top' "$SP/c2_$v.out" | tr -s ' ' | tr '\n' ';') CUDA errors $(grep -c 'CUDA error' "$SP/c2_$v.out")"
done
rm -f "$SP/kl_base.bin"
run() { "$(bin $1)/llama-bench.exe" -m "$MODEL" -ngl 99 -fa on -ctk q4_0 -ctv q4_0 -o jsonl "${@:3}" 2>"$SP/$2.err" > "$SP/$2.jsonl"
  python -c "
import json,sys
for l in open(sys.argv[1]):
    try: e=json.loads(l)
    except Exception: continue
    print('d %d p %d %.2f +- %.2f' % (e['n_depth'], e['n_prompt'], e['avg_ts'], e['stddev_ts']))" "$SP/$2.jsonl" | tr '\n' ';'; }
for rep in 1 2; do for v in base E B C; do
  say "C1 r$rep $v pp512: $(run $v c1_pp512_${v}_r$rep -p 512 -n 0 -r 3 -d 32768,65536,131072)"
  say "C1 r$rep $v pp32: $(run $v c1_pp32_${v}_r$rep -p 32 -n 0 -r 3 -d 65536)"
done; done
say "cfg done"
