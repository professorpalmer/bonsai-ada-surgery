#!/usr/bin/env bash
# P188 (off vs off on the 2060, for the T5 wrong-answer clause; #138 6244718120): the product zip bins, the P170 recipe (1017
# launcher copy, layer off, line pinned 80,640), dense: the code set again (P170 20/24) and the prose set a third time (P170 /
# P183 11/24). Reported: items that flip between dense runs, and how many flips are confident wrong answers.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p188; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$ZIP;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640"
for s in code prose; do
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p188_$s" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p188_$s*.out.log | head -1); E="${O%.out.log}.err.log"
  PYTHONUTF8=1 python p170_drive.py --set $s --arm dense --key-file $KEY --out $R/$s.jsonl > $R/$s.txt 2>&1
  echo "$(date +%T) $s ok $(grep -c '"ok": true' $R/$s.txt) of $(grep -c '"item"' $R/$s.txt); cold $(grep -m1 '"item"' $R/$s.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s; CUDA error lines $(grep -ciE 'cuda error' "$E")" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
