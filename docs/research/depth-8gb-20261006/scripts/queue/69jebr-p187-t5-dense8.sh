#!/usr/bin/env bash
# P187 (T5 on the wrong-answer clause): bin-t5r3, window 32k / sink 1k / tail 1k + dense=7:15:23:31:39:47:55:63 (8 of 16 full-
# attention layers), recipe as P182, the P170 code and prose sets. Reported: ok, and WRONG answers on items dense gets right
# (code: 20 items; prose: the 9 right in both dense runs); the R2 clause asks <= 1 overall. Cold times.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p187; mkdir -p $R
T=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r3)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$T;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0;LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024,dense=7:15:23:31:39:47:55:63"
for s in code prose; do
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p187_$s" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p187_$s*.out.log | head -1); E="${O%.out.log}.err.log"
  PYTHONUTF8=1 python p170_drive.py --set $s --arm dense --key-file $KEY --out $R/$s.jsonl > $R/$s.txt 2>&1
  echo "$(date +%T) $s ok $(grep -c '"ok": true' $R/$s.txt) of $(grep -c '"item"' $R/$s.txt); cold $(grep -m1 '"item"' $R/$s.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s; CUDA error lines $(grep -ciE 'cuda error' "$E"); $(grep -h 'prefill window on' "$E" | sed 's/.*experimental): //')" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
