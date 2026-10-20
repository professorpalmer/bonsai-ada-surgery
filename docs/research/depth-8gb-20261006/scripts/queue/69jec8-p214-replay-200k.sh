#!/usr/bin/env bash
# P214 (after P213: replay rollback +13.9 % decode at 128k on the 2060): the same r6test folder (main's launcher + bin-0070),
# default sizing, replay off then on, one det_answer at 200k each (a cold read + 400 decoded tokens). Reported: the VRAM line,
# decode tok/s at 200k, the prefill time (server log), min free VRAM, 0 CUDA errors / spill lines.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p214; mkdir -p $R
L=$(cygpath -w r6test/start-server.ps1); KEY=$(cygpath -w r6test/artifacts/api_key.txt)
for arm in off on; do
  V=""; [ $arm = on ] && V="BONSAI_RS_REPLAY=1"
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p214_$arm" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p214_$arm*.out.log | head -1); E="${O%.out.log}.err.log"
  grep -hE "^(kv +tiered|vram)" "$O" | sed "s/^/$arm: /" >> $R/run.txt
  ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 5; done ) > $R/$arm.mem.txt & MP=$!
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file "$KEY" --depth 200000 --out $R/${arm}_d200000.txt >> $R/run.txt 2>&1
  kill $MP
  echo "$arm prefill: $(grep 'prompt eval time' "$E" | tail -1 | sed 's/.*prompt eval time = *//')" >> $R/run.txt
  awk '{v=$2+0; if (NR==1||v<m) m=v} END{print "'$arm' trace min free", m, "MiB"}' $R/$arm.mem.txt >> $R/run.txt
  echo "$(date +%T) $arm CUDA error lines: $(grep -ciE 'cuda error' "$E"); spill lines: $(grep -c '^spill' "$O")" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
