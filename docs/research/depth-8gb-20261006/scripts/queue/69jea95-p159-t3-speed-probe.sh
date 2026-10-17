#!/usr/bin/env bash
# P159 (#138 T3 ask, kernel session 16:38Z + the 16:44Z correction): T3 block-sparse prefill attention, 2060 speed probe.
# Engine t3-prefill 0f7a8e0ce (75-real -> bin-t3; T3 and the T2 switches off by default), the bundle-20261016 zip launcher test
# copy (8 GB preset defaults). Cold reads, one fresh server per read (run_arm.sh, quick_tps at one depth):
#   128k dense, 128k T3 (GGML_CUDA_FA_PREFILL_SPARSE=0.5, GGML_CUDA_FA_PREFILL_SPARSE_QTILE=64), 245k dense, 245k T3,
#   128k T3 + GGML_CUDA_FA_CHUNK_STAT=1 + GGML_CUDA_FA_PREFILL_SPARSE_STAT=1 (sm_75 time split; last CHUNK_STAT / T3 op lines).
# Rule (declared by the kernel session): T3 >= 1.15x dense at 245k on the 2060 -> T3 goes to the full 2060 gates. Report TTFT per
# read and the CUDA error count. No quality claim from this run.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p159; mkdir -p $R
S=/c/bonsai/bonsai-ada-surgery
grep -q 0f7a8e0ce <($S/bin-t3/llama-server.exe --version 2>&1) || { echo "bin-t3 is not 0f7a8e0ce" > $R/summary.txt; exit 1; }
BIN='C:/bonsai/bonsai-ada-surgery/bin-t3'; L='C:/bonsai/bonsai-ada-surgery/start-server-1016test.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"; T="$V;GGML_CUDA_FA_PREFILL_SPARSE=0.5;GGML_CUDA_FA_PREFILL_SPARSE_QTILE=64"
arm() { bash run_arm.sh $R $1 "$2" "$L" "$3"; O=$(ls -t logs/*-$1.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$1 CUDA errors: $(grep -c 'CUDA error' "$E")" >> $R/errors.txt; grep -E "CHUNK_STAT|T3 op|PREFILL_SPARSE" "$E" | tail -6 > $R/$1.stat.txt; }
arm dense_128 "$V" 128000; arm t3_128 "$T" 128000
arm dense_245 "$V" 245000; arm t3_245 "$T" 245000
arm t3stat_128 "$T;GGML_CUDA_FA_CHUNK_STAT=1;GGML_CUDA_FA_PREFILL_SPARSE_STAT=1" 128000
python - "$(cygpath -w $R)" > $R/summary.txt <<'PY'
import os, re, sys
R = sys.argv[1]; v = {}
for a in ('dense_128', 't3_128', 'dense_245', 't3_245', 't3stat_128'):
    p = os.path.join(R, a + '.txt')
    m = re.search(r'code\s+depth\s+\d+ \(evaluated (\d+)\): prefill\s+([\d.]+) tok/s\s+ttft\s+([\d.]+)s\s+decode\s+([\d.]+)', open(p, encoding='utf-8', errors='replace').read()) if os.path.exists(p) else None
    v[a] = float(m.group(3)) if m else None
    print(a, m.groups() if m else 'MISSING')
for d in ('128', '245'):
    a, b = v.get('dense_' + d), v.get('t3_' + d)
    print(f'{d}k: dense {a} s, T3 {b} s, ratio {a / b:.3f}x' if a and b else f'{d}k: n/a')
r = v['dense_245'] / v['t3_245'] if v.get('dense_245') and v.get('t3_245') else None
print('rule (>= 1.15x at 245k):', 'MET' if r and r >= 1.15 else 'NOT MET', r)
PY
cat $R/errors.txt >> $R/summary.txt; for a in t3_128 t3_245 t3stat_128; do echo "== $a"; cat $R/$a.stat.txt; done >> $R/summary.txt
