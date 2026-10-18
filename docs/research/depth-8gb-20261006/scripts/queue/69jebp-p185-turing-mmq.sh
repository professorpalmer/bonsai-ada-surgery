#!/usr/bin/env bash
# P185 (Turing MMQ table for PTQ1_0, fork turing-mmq 7d262ec31 on the bundle-20261017 engine): variants built with
# GGML_CUDA_TURING_PTQ1_VARIANT 1 (occupancy 2, I 128) and 2 (occupancy 2, I 64); the zip bins = the Ampere table (0).
# Gates (declared before the run): per variant, test-backend-ops test -o MUL_MAT (PTQ1_0 cases) all pass; then perf MUL_MAT
# 4096 x 512 x 14336 (P173 zip 28.3 TFLOPS). A variant must pass and be >= 5 % faster to go on: then one cold 64k read
# (p168_read.py) on the 1017 launcher copy with that variant vs zip (P183-class 64k ~207 s), greedy det_answer 4k hash vs zip
# reported (MMQ tiles change the sum order, so a hash change is expected; report it).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p185; mkdir -p $R
for i in $(seq 1 180); do grep -q "mmqv2 exit" receipts/build_ahead.log && break; sleep 10; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; sleep 3
ZIPU="$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")"
best=""; bestv=0
for arm in zip mmqv1 mmqv2; do
  D=$ZIPU; [ $arm != zip ] && D=/c/bonsai/bonsai-ada-surgery/bin-$arm
  [ -f "$D/test-backend-ops.exe" ] || { echo "$arm: no bins" >> $R/run.txt; continue; }
  "$D/test-backend-ops.exe" test -o MUL_MAT -b CUDA0 -p "type_a=ptq1_0" < /dev/null > $R/test_$arm.txt 2>&1
  pass=$(grep -cE "^\s+MUL_MAT.*OK" $R/test_$arm.txt); fail=$(grep -cE "FAIL" $R/test_$arm.txt)
  "$D/test-backend-ops.exe" perf -o MUL_MAT -b CUDA0 -p "type_a=ptq1_0.*m=4096,n=512,k=14336" < /dev/null > $R/perf_$arm.txt 2>&1
  tf=$(python -c "
import re, sys
t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
m = re.search(r'type_a=ptq1_0.*?m=4096,n=512.*?(\d+\.\d+) TFLOPS', t, re.S)
print(m.group(1) if m else '0')
" $R/perf_$arm.txt)
  echo "$(date +%T) $arm: test OK $pass FAIL $fail; perf $tf TFLOPS" >> $R/run.txt
  if [ $arm != zip ] && [ "$fail" = 0 ] && [ "$pass" -gt 0 ]; then
    better=$(python -c "import sys; print(1 if float(sys.argv[1]) > float(sys.argv[2]) else 0)" "$tf" "$bestv")
    [ "$better" = 1 ] && { best=$arm; bestv=$tf; }
  fi
  [ $arm = zip ] && ztf=$tf
done
echo "best variant: $best ($bestv vs zip $ztf)" >> $R/run.txt
go=$(python -c "import sys; print(1 if sys.argv[1] and float(sys.argv[2]) >= 1.05*float(sys.argv[3]) else 0)" "$best" "${bestv:-0}" "${ztf:-1}")
if [ "$go" = 1 ]; then
  L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
  for arm in zip $best; do
    B=$(cygpath -w "$(cd "$ZIPU" && pwd)"); [ $arm != zip ] && B=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-$arm)
    for t in r64 d4; do
      powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
      schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
      powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p185_${arm}_$t" -Launcher "$L" -Vars "BONSAI_BIN=$B;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640" >/dev/null 2>&1
      for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
      if [ $t = r64 ]; then PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 64000 --salt p185_$arm >> $R/run.txt 2>&1
      else PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/${arm}_d4.txt >> $R/run.txt 2>&1; fi
      E=$(ls -t logs/*p185_${arm}_$t*.err.log | head -1); echo "$arm $t CUDA error lines: $(grep -ciE 'cuda error' "$E")" >> $R/run.txt
    done
  done
else
  echo "no variant passed the >= 5 % gate: no server runs" >> $R/run.txt
fi
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
