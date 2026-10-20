#!/usr/bin/env bash
# P215 (after P213: with replay rollback the launcher charges only +7 MiB per extra draft token, not a 144 MiB plane): draft
# size on the 8 GB preset with replay on. r6test (main's launcher + bin-0070), defaults + BONSAI_RS_REPLAY=1, arms in one block:
# d11 = BONSAI_SPEC 1 / SPEC_DEEP 1 (the 8 GB default), d21 = 2 / 1, d22 = 2 / 2, d33 = 3 / 3. Per arm: det_answer 4k, 64k and
# 128k (each a cold read + 400 decoded tokens), the VRAM line, min free, 0 CUDA errors / spill lines. Reported: decode tok/s per
# depth and arm (an arm wins at a depth if it beats d11 by more than 3 %); greedy text may differ by rounding (drafting is not
# batch-invariant in attention), reported, not gated.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p215; mkdir -p $R
L=$(cygpath -w r6test/start-server.ps1); KEY=$(cygpath -w r6test/artifacts/api_key.txt)
for arm in d11 d21 d22 d33; do
  s=${arm:1:1}; d=${arm:2:1}
  V="BONSAI_RS_REPLAY=1;BONSAI_SPEC=$s;BONSAI_SPEC_DEEP=$d"
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p215_$arm" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p215_$arm*.out.log | head -1); E="${O%.out.log}.err.log"
  grep -hE "^(kv +tiered|spec)" "$O" | sed "s/^/$arm: /" >> $R/run.txt
  ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 5; done ) > $R/$arm.mem.txt & MP=$!
  for dd in 4000 64000 128000; do
    # a unique first line per request, so no prompt-cache reuse between depths
    PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file "$KEY" --depth $dd --out $R/${arm}_d$dd.txt 2>&1 | sed "s/^/$arm d$dd: /" >> $R/run.txt
    powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
    schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
    powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p215_${arm}_r" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
    for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  done
  kill $MP
  awk '{v=$2+0; if (NR==1||v<m) m=v} END{print "'$arm' trace min free", m, "MiB"}' $R/$arm.mem.txt >> $R/run.txt
  echo "$(date +%T) $arm CUDA error logs: $(grep -l 'CUDA error' logs/*p215_${arm}*.err.log 2>/dev/null | wc -l); spill lines: $(cat logs/*p215_${arm}*.out.log | grep -c '^spill')" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
