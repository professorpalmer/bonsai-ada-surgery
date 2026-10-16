#!/usr/bin/env bash
# P154 (#138 T2a ask, 4070 08:58Z): GQA packing in the prefill attention kernel on sm_75. Engine t2-prefill 2724a8349
# (= product-0059 ab9481005 + fattn.cu: GGML_CUDA_FA_PREFILL_NCOLS2=2), 75-real build (incremental in build-q3kv) -> bin-t2.
# Launcher: the bundle-20261016 zip launcher test copy (P150), defaults (q3_0, auto sparse).
# Arms: COLD prefill, fresh server per prompt: default vs GGML_CUDA_FA_PREFILL_NCOLS2=2, at 64k and 128k, alternated x2
# (def, t2, def, t2 per depth). Byte check: one 4k code answer (det_answer.py) on each setting.
# Rule (declared before the run): exact claim holds if the 4k answers are byte-identical; speed = mean cold TTFT per depth,
# t2 vs def. Expected (4070): attention part up to ~1.3x faster. Report TTFT, prefill tok/s and decode per arm.
# The build runs first, before any GPU arm, so it does not touch the timings.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p154; mkdir -p $R
S=/c/bonsai/bonsai-ada-surgery; W=$S/vendor/prism-q3kv
( cd $W && git checkout -q --detach 2724a8349 && git log --oneline -1 ) > $R/build.txt 2>&1
echo "$(date +%T) build t2-prefill 2724a8349 in build-q3kv" >> receipts/build_ahead.log
cmd //c 'C:\bonsai\bonsai-ada-surgery\tooling\build-q3kv\build.bat' > logs/build-t2.log 2>&1; echo "build exit $?" >> $R/build.txt
rm -rf $S/bin-t2; cp -r $S/tooling/build-q3kv/bin $S/bin-t2
for f in cublas64_13.dll cublasLt64_13.dll cudart64_13.dll nvJitLink_130_0.dll nvvm64_40_0.dll; do cp $S/bin-q3sparse/$f $S/bin-t2/; done
echo "version: $($S/bin-t2/llama-server.exe --version 2>&1 | grep -i commit)" >> $R/build.txt
grep -q "2724a8349" $R/build.txt || { echo "build failed or wrong commit" >> $R/build.txt; cp $R/build.txt $R/summary.txt; exit 1; }
echo "FLASH_ATTN_EXT: $($S/bin-t2/test-backend-ops.exe -o FLASH_ATTN_EXT -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')" >> $R/build.txt
echo "FLASH_ATTN_EXT NCOLS2=2: $(GGML_CUDA_FA_PREFILL_NCOLS2=2 $S/bin-t2/test-backend-ops.exe -o FLASH_ATTN_EXT -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')" >> $R/build.txt
BIN='C:/bonsai/bonsai-ada-surgery/bin-t2'; L='C:/bonsai/bonsai-ada-surgery/start-server-1016test.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"; T="$V;GGML_CUDA_FA_PREFILL_NCOLS2=2"
for d in 64000 128000; do
  bash run_arm.sh $R def_${d}_r1 "$V" "$L" "$d"; bash run_arm.sh $R t2_${d}_r1 "$T" "$L" "$d"
  bash run_arm.sh $R def_${d}_r2 "$V" "$L" "$d"; bash run_arm.sh $R t2_${d}_r2 "$T" "$L" "$d"
done
sed -e 's#python $B/bench/quick_tps.py --base $BASE $KEYARG --depth $d#python C:/bonsai/8gb/det_answer.py --base $BASE $KEYARG --depth $d --out C:/bonsai/8gb/'$R'/$TAG.answer.txt#' run_arm.sh > $R/run_det.sh
bash $R/run_det.sh $R det_def "$V" "$L" "4000"; bash $R/run_det.sh $R det_t2 "$T" "$L" "4000"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - "$(cygpath -w $R)" > $R/summary.txt <<'EOF'
import os, re, sys, hashlib
R = sys.argv[1]
def first(tag):
    p = os.path.join(R, tag + '.txt')
    if not os.path.exists(p): return None
    for l in open(p, encoding='utf-8', errors='replace'):
        m = re.match(r'code\s+depth\s+(\d+) \(evaluated (\d+)\): prefill\s+([\d.]+) tok/s\s+ttft\s+([\d.]+)s\s+decode\s+([\d.]+)', l)
        if m: return dict(ev=int(m.group(2)), pp=float(m.group(3)), ttft=float(m.group(4)), tg=float(m.group(5)))
for d in (64000, 128000):
    print(f'== cold {d}')
    res = {}
    for arm in ('def', 't2'):
        rows = [first(f'{arm}_{d}_r{i}') for i in (1, 2)]
        print(arm, rows)
        ok = [r for r in rows if r]
        if ok: res[arm] = sum(r['ttft'] for r in ok) / len(ok)
    if len(res) == 2: print(f"mean cold TTFT def {res['def']:.1f} s, t2 {res['t2']:.1f} s, ratio {res['def'] / res['t2']:.3f}x")
h = []
for t in ('det_def', 'det_t2'):
    p = os.path.join(R, t + '.answer.txt')
    h.append(hashlib.sha256(open(p, 'rb').read()).hexdigest() if os.path.exists(p) else None)
print('4k answer bytes:', 'IDENTICAL' if h[0] and h[0] == h[1] else 'DIFFERENT', h)
EOF
cat $R/build.txt >> $R/summary.txt
