#!/usr/bin/env bash
# P210 (optional post-zip check of bundle-20261018d on the 2060, #138 6256728882): zip 63f3af82... SHA match; bins = 18c (checked
# in P209); the layer change: the save BEFORE the request is a delta too. 12 turns of the P164 session through the 18d zip's own
# launcher + layer with BONSAI_SLOT_CACHE_AFTER=0 (the save-before path), GROW 4096 exported, restarts before turns 4 / 7 / 10:
# answers equal to P205's after=0 arm on 12/12; saves before the request appear as deltas (small files, short save times);
# restores work; 0 CUDA errors.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p210; mkdir -p $R
ZR=release_1018d/x
[ -e "$ZR/models" ] || powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$ZR")/models' -Target 'C:/bonsai/bonsai-ada-surgery/models'" < /dev/null >> $R/zip.txt 2>&1
mkdir -p "$ZR/artifacts"; cp -n C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt "$ZR/artifacts/api_key.txt"
KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
L=$(cygpath -w $ZR/start-server.ps1)
RA=$R/arm; mkdir -p $RA; rm -rf slots210; mkdir -p slots210
SW="C:/bonsai/8gb/slots210"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
export BONSAI_SLOT_CACHE_AFTER=0; unset BONSAI_SLOT_CACHE_CHAIN
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p210_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 150); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done
  echo "$(date +%T) WARN layer still busy after 300 s" >> $RA/run.txt; }
serve() { if [ -n "$LP" ]; then idle; ls -l slots210 > $RA/slot_files_$1.txt; kill $LP 2>/dev/null; fi; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p210_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $RA/run.txt; }
for k in $(seq 1 12); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
idle; ls -l slots210 > $RA/slot_files_end.txt; [ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "lc-saving files left: $(ls slots210 | grep -c 'lc-saving')" >> $RA/run.txt
rm -rf slots210
python - "$(cygpath -w $RA/turns.jsonl)" "$(cygpath -w receipts/p205/after0/turns.jsonl)" >> $R/run.txt <<'PY2'
import json, sys
a = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
b = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[2], encoding='utf-8')}
same = sum(1 for r in a if (r['answer'] or '').strip() == (b[r['turn']]['answer'] or '').strip())
print('answers equal to P205 after=0:', same, 'of', len(a), '(gate 12/12)')
for r in a: print('turn', r['turn'], 'wall', r['wall_s'], 'P205', b[r['turn']]['wall_s'])
PY2
grep -h "delta saves\|restored\|saved\|failed" $RA/layer_*.log >> $R/run.txt
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p210_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
