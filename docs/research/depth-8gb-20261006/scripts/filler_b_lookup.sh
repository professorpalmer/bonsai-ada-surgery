#!/usr/bin/env bash
source /c/bonsai/8gb/preempt_lib.sh   # yield the GPU to queued jobs
# Default sweep B: lookup A/B repeat (variance), depth 0 and 64k, lookup 0 and 1.
cd /c/bonsai/8gb; D=receipts/filler/lookup_$(date +%m%d_%H%M); mkdir -p $D
L='C:/bonsai/bonsai-ada-surgery/start-server-262test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt; B=$(cat receipts/newest_bin 2>/dev/null || echo bin-lookup)
for d in 0 64000; do for lk in 0 1; do
  [ -n "$(ls /c/bonsai/8gb/queue/pending 2>/dev/null)" ] && { echo "yield to queue" > $D/yield.txt; powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; exit 0; }
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag fill_lk${lk}_d$d -Launcher "$L" -Vars "BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/$B;BONSAI_LAYER=0;BONSAI_LOOKUP=$lk" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag lk${lk}_d$d --out $D/ab.jsonl --depth $d > $D/lk${lk}_d$d.out.txt 2>&1
done; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
