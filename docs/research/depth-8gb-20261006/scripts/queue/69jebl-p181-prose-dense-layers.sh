#!/usr/bin/env bash
# P181 (T5 quality knob on the prose set, after the d1cc7a4bd hybrid-input fix; P180 must show dense=15 at 4k = the plain hash):
# bin-t5r3, recipe as P178, default 32k chunks. Prose set (dense 11/24; T5 16k 5/24; 32k 9/24). Arms:
#   e4: window 16k + dense=15:31:47:63 (4 evenly spaced full-attention layers)
#   l4: window 16k + dense=51:55:59:63 (the last 4)
#   w32e4: window 32k + dense=15:31:47:63
# Report ok vs dense item by item and the cold time. Stop if P180 C or D differs from P180 B.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p181; mkdir -p $R
python -c "
import hashlib, sys
h = {a: hashlib.sha256(open('receipts/p180/' + a + '.txt', 'rb').read()).hexdigest()[:16] for a in 'ABCD'}
print('P180', h); sys.exit(0 if h['B'] == h['C'] == h['D'] else 1)
" >> $R/run.txt 2>&1 || { echo "$(date +%T) P180 dense-layer check failed: stop" >> $R/run.txt; exit 0; }
T=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r3)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_BIN=$T;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
for arm in e4 l4 w32e4; do
  case $arm in
    e4)    WV="window=16384,sink=1024,tail=1024,dense=15:31:47:63";;
    l4)    WV="window=16384,sink=1024,tail=1024,dense=51:55:59:63";;
    w32e4) WV="window=32768,sink=1024,tail=1024,dense=15:31:47:63";;
  esac
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p181_$arm" -Launcher "$L" -Vars "$B0;LLAMA_PREFILL_WINDOW=$WV" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p181_$arm*.out.log | head -1); E="${O%.out.log}.err.log"
  PYTHONUTF8=1 python p170_drive.py --set prose --arm dense --key-file $KEY --out $R/prose_$arm.jsonl > $R/prose_$arm.txt 2>&1
  echo "$(date +%T) $arm ok $(grep -c '"ok": true' $R/prose_$arm.txt) of $(grep -c '"item"' $R/prose_$arm.txt); cold $(grep -m1 '"item"' $R/prose_$arm.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s; CUDA error lines $(grep -ciE 'cuda error' "$E"); $(grep -h 'prefill window on' "$E" | sed 's/.*experimental): //')" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
