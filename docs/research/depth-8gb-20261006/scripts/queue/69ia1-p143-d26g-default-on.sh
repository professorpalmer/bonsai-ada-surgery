#!/usr/bin/env bash
# P143 = D26g (#105, step 1, data only): can BONSAI_SPARSE=1 be the 8 GB default now that q3_0 is? bundle-20261015 zip bins
# (release_1015/x/bin, from P142), launcher test copy of 0cbd0dcc (start-server-1015test.ps1), launcher defaults (q3_0 on 8 GB).
# Arms: off (default) vs sparse (BONSAI_SPARSE=1, budget max(12288, host tail x 0.125)).
#   (a) shallow: alternated x2, one server per arm, 64k -> 80k -> 96k -> 112k -> 128k (extends);
#   (b) deep: one server per arm, 160k -> 245k, 10 s trace (245k minimum free).
#   (c) [added before the run, 4070 request 12:17Z after D26g-pre]: sparse with GGML_CUDA_FA_SPARSE_MIN_HOST=65536, one server,
#       112k -> 128k -> 160k (where is the 2060's q3_0 crossover).
# Gate (declared in #105 before the runs, copied here): no depth <= 128k loses more than 2 % (sparse vs off, mean of 2 rounds),
# and the 160k / 245k gains stand (R11-type, with q3_0); 0 one-token; report both launcher VRAM lines and the 245k trace minimum.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p143; mkdir -p $R
[ -d release_1015/x ] || { echo "no release_1015/x (P142 extracts it)" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$(find release_1015/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-1015test.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
arm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.trace.txt & MP=$!
  bash run_arm.sh $R "$@"; kill $MP
  awk -F", " '{split($1,a," "); v=$2+0; if (v>4000000) v-=4194304; if (NR==1||v<m) {m=v; t=a[1]}} END{print "trace min free", m, "MiB at", t, "over", NR, "samples"}' $R/$1.trace.txt >> $R/$1.txt
  E=$(ls -t logs/*-$1.err.log | head -1); O="${E%err.log}out.log"
  echo "sparse_mask lines: $(grep -c ggml_cuda_fa_sparse_mask "$E")" >> $R/$1.txt; grep -hE "^(kv|8gb|window) |VRAM line|budget" "$O" > $R/$1.launcher.txt; }
for r in 1 2; do
  arm off_r$r "$V" "$L" "64000 80000 96000 112000 128000"
  arm sp_r$r "$V;BONSAI_SPARSE=1" "$L" "64000 80000 96000 112000 128000"
done
arm sp_mh64k "$V;BONSAI_SPARSE=1;GGML_CUDA_FA_SPARSE_MIN_HOST=65536" "$L" "112000 128000 160000"
arm deep_off "$V" "$L" "160000 245000"
arm deep_sp "$V;BONSAI_SPARSE=1" "$L" "160000 245000"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for a in off_r1 sp_r1 off_r2 sp_r2 sp_mh64k deep_off deep_sp; do f=$R/$a.txt; echo "== $a: $(grep -c '(1 tok)' $f) one-token"; cat $R/$a.launcher.txt
    grep -E "loaded|depth|mean decode|did not|trace min|sparse_mask lines" $f | sed -E 's/ttft +[0-9.]+s +//'; done
  python - <<'PY'
import re
def means(a):
    try: return [float(x) for x in re.findall(r'mean decode ([0-9.]+)', open(f'receipts/p143/{a}.txt').read())]
    except FileNotFoundError: return []
o=[ (x+y)/2 for x,y in zip(means('off_r1'), means('off_r2')) ]; s=[ (x+y)/2 for x,y in zip(means('sp_r1'), means('sp_r2')) ]
for d,a,b in zip((64,80,96,112,128),o,s): print(f'{d}k: off {a:.2f} sparse {b:.2f} ({(b/a-1)*100:+.1f} %)')
do,ds=means('deep_off'),means('deep_sp')
for d,a,b in zip((160,245),do,ds): print(f'{d}k: off {a:.1f} sparse {b:.1f} ({b/a:.2f}x)')
m=means('sp_mh64k'); print('MIN_HOST 65536 arm (112k / 128k / 160k):', m)
PY
} > $R/summary.txt
