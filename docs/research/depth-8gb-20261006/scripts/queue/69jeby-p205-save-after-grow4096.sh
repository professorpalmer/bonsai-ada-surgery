#!/usr/bin/env bash
# P205 (= P204 rerun with BONSAI_SLOT_CACHE_GROW=4096 exported for the layer: in P204 the external layer runner did not get the
# launcher's 8 GB default, so both arms ran at 8192. The release session's 2060 request, #138 6250909875, called "P201" there): save after the answer on bundle-20261018
# (zip f8347f4e..., 616,677,417 B; engine c5e73e7d81 = product + 0067), the zip's own launcher, defaults (GROW 4096 on 8 GB),
# BONSAI_SLOT_SAVE_PATH, the zip's layer via p204_layer.py --cache. Arms in one block, "after" first: BONSAI_SLOT_CACHE_AFTER=1,
# then =0. P164's 30-turn session (p155_turn.py), a restart before every 3rd turn, a fresh slot folder per arm; before each
# restart, wait until GET /layer/slot-cache returns "busy": false (max 300 s).
# Gates A-F (the release session's): A answers equal 30/30; B restart turns 4-28 mean >= 30 % lower; C normal turns mean at most
# 10 % higher; D arm wall time at most "before" + 5 %; E the prefix test passes in the layer log, >= 1 save after the answer,
# saves at most "before" + 2; F 0 CUDA errors, no lc-saving-* files left.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p205; mkdir -p $R
ZR=release_1018/x
[ -e "$ZR/models" ] || powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$ZR")\models' -Target 'C:\bonsai\bonsai-ada-surgery\models'" < /dev/null >> $R/zip.txt 2>&1
mkdir -p "$ZR/artifacts"; cp -n C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt "$ZR/artifacts/api_key.txt"
python -c "
import sys
b=open(sys.argv[1],'rb').read(); print('zip launcher control bytes:', sum(1 for c in b if c<32 and c not in (9,10,13)))
" "$(cygpath -w $ZR/start-server.ps1)" >> $R/zip.txt
L=$(cygpath -w $ZR/start-server.ps1); KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
run_arm() {
A=$1; RA=$R/after$A; mkdir -p $RA; rm -rf slots205_$A; mkdir -p slots205_$A
SW="C:/bonsai/8gb/slots205_$A"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_AFTER=$A
export BONSAI_SLOT_CACHE_GROW=4096   # the 8 GB launcher default (#182), set here because the layer runs outside the launcher
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p204_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 150); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done
  echo "$(date +%T) WARN layer still busy after 300 s" >> $RA/run.txt; }
serve() { if [ -n "$LP" ]; then idle; kill $LP 2>/dev/null; fi; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p205_a${A}_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $RA/run.txt; }
for k in $(seq 1 30); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
idle; [ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "lc-saving files left: $(ls slots205_$A | grep -c 'lc-saving')" >> $RA/run.txt
grep -h "^8gb\|^window" $(ls -t logs/*p205_a${A}_t1.out.log | head -1) >> $RA/run.txt
rm -rf slots205_$A
}
run_arm 1
run_arm 0
python - "$(cygpath -w $R)" > $R/summary.txt <<'PY'
import glob, json, os, statistics, sys
R = sys.argv[1]
rows = {a: [json.loads(l) for l in open(os.path.join(R, 'after' + a, 'turns.jsonl'), encoding='utf-8')] for a in '10'}
def split(rs):
    rst = [r['wall_s'] for r in rs if 4 <= r['turn'] <= 28 and (r['turn'] - 1) % 3 == 0]
    nrm = [r['wall_s'] for r in rs if r['turn'] > 1 and (r['turn'] - 1) % 3 != 0]
    return statistics.mean(rst), statistics.mean(nrm), sum(r['wall_s'] for r in rs)
ra, na, ta = split(rows['1']); rb, nb, tb = split(rows['0'])
same = sum(1 for x, y in zip(rows['1'], rows['0']) if (x['answer'] or '').strip() == (y['answer'] or '').strip())
print('A answers equal', same, 'of 30', 'PASS' if same == 30 else 'FAIL')
print('B restart mean after', round(ra, 1), 'before', round(rb, 1), 'change', round(100 * (ra / rb - 1), 1), '% (gate <= -30)')
print('C normal mean after', round(na, 1), 'before', round(nb, 1), 'change', round(100 * (na / nb - 1), 1), '% (gate <= +10)')
print('D total after', round(ta), 'before', round(tb), 'change', round(100 * (ta / tb - 1), 1), '% (gate <= +5)')
def logs(a):
    t = ''.join(open(f, encoding='utf-8', errors='replace').read() for f in glob.glob(os.path.join(R, 'after' + a, 'layer_*.log')))
    return t.count('after-answer test'), t.count('after-answer test') - t.count(' fail '), t.count('saved after the answer'), t.count('] saved ') - t.count('] saved after the answer')
for a in '10':
    print('E arm after=' + a, 'tests / pass / saved-after / saved-before:', logs(a))
PY
echo "F CUDA error logs: $(grep -l 'CUDA error' logs/*p205_*.err.log 2>/dev/null | wc -l)" >> $R/summary.txt
grep -h "lc-saving files left" $R/after*/run.txt >> $R/summary.txt
