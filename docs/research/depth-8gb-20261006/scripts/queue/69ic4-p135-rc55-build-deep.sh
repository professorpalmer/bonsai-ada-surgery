#!/usr/bin/env bash
# P135 (#21 / release-20261014 R06, pre-run on the release candidate): product-0055 4de618549 (patch 0055: sparse with int8
# bounds, budget max(B, host tail x FRAC 1/16), the MIN_HOST routing fix) built 75-real in prism-tiergraphs (branch
# product-0055-rc-2060) -> bin-rc55, with launcher #49 d927d6b (sparse opt-in, BONSAI_SPARSE=1) as a test copy + BONSAI_BIN.
# Driver 610.88. Arms (one server each, 160k cold -> 245k): dense (launcher default, sparse off), sparse (BONSAI_SPARSE=1).
# Gates (declared here, before the run; R06 items): op tests 0 FAIL; sparse >= 1.8x dense at 160k and 245k; 0 one-token;
# trace min free >= 60 MiB in both arms (the 4070 is checking the launcher headroom: report the minimum either way).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p135; mkdir -p $R
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
H=$(git -C /c/bonsai/bonsai-ada-surgery/vendor/prism-tiergraphs rev-parse --short HEAD); echo "source $H; driver $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)" > $R/build.txt
ok=0; for i in 1 2 3; do cmd //c 'C:\bonsai\bonsai-ada-surgery\tooling\build-tiergraphs\build.bat' > logs/build-rc55.log 2>&1
  if [ -f /c/bonsai/bonsai-ada-surgery/tooling/build-tiergraphs/bin/llama-server.exe ] && ! grep -q "build stopped" logs/build-rc55.log && ! grep -qE "error C|error:|LNK[0-9]+" logs/build-rc55.log; then ok=1; echo "build ok try $i $(date +%T)" >> $R/build.txt; break; fi; done
[ $ok = 1 ] || { echo "build FAILED"; cat $R/build.txt; grep -E "error" logs/build-rc55.log | head; } > $R/summary.txt
[ $ok = 1 ] || exit 1
B=/c/bonsai/bonsai-ada-surgery/bin-rc55
rm -rf $B && cp -r /c/bonsai/bonsai-ada-surgery/tooling/build-tiergraphs/bin $B
for f in /c/bonsai/bonsai-ada-surgery/bin-0046/*.dll; do b=$(basename $f); [ -f $B/$b ] || cp $f $B/; done
for o in FLASH_ATTN_EXT GATED_DELTA_NET; do echo "$o: $($B/test-backend-ops.exe -o $o -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r') FAIL lines $($B/test-backend-ops.exe -o $o -b CUDA0 < /dev/null 2>&1 | grep -c FAIL)" >> $R/tests.txt; done
grep -qE "FAIL lines [1-9]" $R/tests.txt && { echo "op tests FAIL"; cat $R/build.txt $R/tests.txt; } > $R/summary.txt && exit 1
L='C:/bonsai/bonsai-ada-surgery/start-server-rc55.ps1'
V="BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/bin-rc55;BONSAI_LAYER=0"
arm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.trace.txt & MP=$!
  bash run_arm.sh $R "$@"; kill $MP
  awk -F", " '{split($1,a," "); v=$2+0; if (v>4000000) v-=4194304; if (NR==1||v<m) {m=v; t=a[1]}} END{print "trace min free", m, "MiB at", t, "over", NR, "samples"}' $R/$1.trace.txt >> $R/$1.txt
  E=$(ls -t logs/*-$1.err.log | head -1); O="${E%err.log}out.log"
  echo "sparse_mask lines: $(grep -c ggml_cuda_fa_sparse_mask "$E")" >> $R/$1.txt; grep -hE "^(kv|8gb|window) |VRAM line" "$O" > $R/$1.launcher.txt; }
sumarms() { for a in "$@"; do f=$R/$a.txt; echo "== $a: $(grep -c "(1 tok)" $f) one-token"; cat $R/$a.launcher.txt 2>/dev/null; grep -E "loaded|depth|mean decode|did not|trace min|sparse_mask lines" $f | sed -E "s/ttft +[0-9.]+s +//"; done; }
arm dense "$V" "$L" "160000 245000"
arm sparse "$V;BONSAI_SPARSE=1" "$L" "160000 245000"
{ cat $R/build.txt $R/tests.txt; sumarms dense sparse; } > $R/summary.txt
