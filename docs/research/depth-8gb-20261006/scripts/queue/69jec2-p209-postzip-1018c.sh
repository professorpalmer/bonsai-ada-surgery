#!/usr/bin/env bash
# P209 (post-zip check of bundle-20261018c on the 2060, asked in #138 6254974925): zip 6111693d... SHA match; engine a6d4fc698f
# (patches 0068-0069: delta saves). (1) det_answer 4k: zip 18b then zip 18c, in one block: equal sha. (2) a cold 64k read on 18c
# (stock 306.5-307.7 tok/s). (3) 12 turns of P164's session through the 18c zip's own launcher + its layer (save after the answer
# and delta saves on by default; GROW 4096 exported because the layer runs outside the launcher), restarts before turns 4, 7,
# 10: answers equal to P205's after=1 arm (the same defaults minus deltas) on 12/12; the layer log says "delta saves on"; the slot
# folder holds small delta files; restores work after each restart; 0 CUDA errors.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p209; mkdir -p $R
ZR=release_1018c/x
for Z in release_1018c/x release_1018b/x; do
  [ -e "$Z/models" ] || powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$Z")/models' -Target 'C:/bonsai/bonsai-ada-surgery/models'" < /dev/null >> $R/zip.txt 2>&1
  mkdir -p "$Z/artifacts"; cp -n C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt "$Z/artifacts/api_key.txt"
done
KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
for arm in z18b z18c; do
  case $arm in z18b) LL=$(cygpath -w release_1018b/x/start-server.ps1);; z18c) LL=$(cygpath -w $ZR/start-server.ps1);; esac
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p209_$arm" -Launcher "$LL" -Vars "" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/${arm}_d4.txt >> $R/run.txt 2>&1
  [ $arm = z18c ] && PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 64000 --salt p209 >> $R/run.txt 2>&1
done
python -c "
import hashlib, sys
h = {a: hashlib.sha256(open(sys.argv[1] + '/' + a + '_d4.txt', 'rb').read()).hexdigest()[:16] for a in ('z18b', 'z18c')}
print('identity', h, 'PASS' if h['z18b'] == h['z18c'] else 'DIFFERENT')
" $R >> $R/run.txt
L=$(cygpath -w $ZR/start-server.ps1)
RA=$R/arm; mkdir -p $RA; rm -rf slots209; mkdir -p slots209
SW="C:/bonsai/8gb/slots209"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
unset BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p209_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 150); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done
  echo "$(date +%T) WARN layer still busy after 300 s" >> $RA/run.txt; }
serve() { if [ -n "$LP" ]; then idle; ls -l slots209 > $RA/slot_files_$1.txt; kill $LP 2>/dev/null; fi; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p209_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $RA/run.txt; }
for k in $(seq 1 12); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
idle; ls -l slots209 > $RA/slot_files_end.txt; [ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "lc-saving files left: $(ls slots209 | grep -c 'lc-saving')" >> $RA/run.txt
rm -rf slots209
python - "$(cygpath -w $RA/turns.jsonl)" "$(cygpath -w receipts/p205/after1/turns.jsonl)" >> $R/run.txt <<'PY2'
import json, sys
a = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
b = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[2], encoding='utf-8')}
same = sum(1 for r in a if (r['answer'] or '').strip() == (b[r['turn']]['answer'] or '').strip())
print('answers equal to P205 after=1:', same, 'of', len(a), '(gate 12/12)')
for r in a: print('turn', r['turn'], 'wall', r['wall_s'], 'P205', b[r['turn']]['wall_s'])
PY2
grep -h "delta saves\|restored\|saved after\|failed" $RA/layer_*.log >> $R/run.txt
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p209_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
