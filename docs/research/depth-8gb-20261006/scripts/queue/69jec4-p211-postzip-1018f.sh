#!/usr/bin/env bash
# P211 (post-zip check of bundle-20261018f on the 2060, not asked): zip b31859f3... SHA match; bins = 18c (P209); the layer saves
# after every answer of a long conversation as a delta and restores exactly to the last answer (#198). 12 turns of the P164 session through the 18d zip's own
# launcher + layer with the defaults (save after every answer), GROW 4096 exported, restarts before turns 4 / 7 / 10:
# answers equal to P205's after=1 arm on 12/12; saves after the answer are deltas;
# restores work; 0 CUDA errors.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p211; mkdir -p $R
ZR=release_1018f/x
[ -e "$ZR/models" ] || powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$ZR")/models' -Target 'C:/bonsai/bonsai-ada-surgery/models'" < /dev/null >> $R/zip.txt 2>&1
mkdir -p "$ZR/artifacts"; cp -n C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt "$ZR/artifacts/api_key.txt"
KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
L=$(cygpath -w $ZR/start-server.ps1)
RA=$R/arm; mkdir -p $RA; rm -rf slots211; mkdir -p slots211
SW="C:/bonsai/8gb/slots211"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
unset BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN BONSAI_SLOT_CACHE_EVERY
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p211_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 150); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done
  echo "$(date +%T) WARN layer still busy after 300 s" >> $RA/run.txt; }
serve() { if [ -n "$LP" ]; then idle; ls -l slots211 > $RA/slot_files_$1.txt; kill $LP 2>/dev/null; fi; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p211_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $RA/run.txt; }
for k in $(seq 1 12); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
idle; ls -l slots211 > $RA/slot_files_end.txt; [ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "lc-saving files left: $(ls slots211 | grep -c 'lc-saving')" >> $RA/run.txt
rm -rf slots211
python - "$(cygpath -w $RA/turns.jsonl)" "$(cygpath -w receipts/p205/after1/turns.jsonl)" >> $R/run.txt <<'PY2'
import json, sys
a = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
b = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[2], encoding='utf-8')}
same = sum(1 for r in a if (r['answer'] or '').strip() == (b[r['turn']]['answer'] or '').strip())
print('answers equal to P205 after=1:', same, 'of', len(a), '(gate 12/12)')
for r in a: print('turn', r['turn'], 'wall', r['wall_s'], 'P205', b[r['turn']]['wall_s'])
PY2
grep -h "delta saves\|restored\|saved\|failed" $RA/layer_*.log >> $R/run.txt
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p211_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
