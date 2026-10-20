#!/usr/bin/env bash
# P225 (P224: on bundle-20261019c, the 200k short turn D2 after a restart answered Q2 "vault 4: 9320"; the true largest is vault 7
# 9387; at 4k the same Q2 is right): is the restore exact, or does the model fail at 200k? The same conversation (P224 arm D:
# depth 200000, turns 1-4, --short 2,4) on ONE server with no restart (arm M, the in-memory reference), the same zip, launcher,
# layer runner and env. Gate (declared before the run): M answers byte-equal to P224 D on turns 1-4 -> the restore is exact and
# the Q2 / Q3 errors are the model; any difference -> the restore changes answers (a new issue with both transcripts).
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p225; mkdir -p $R
ZR=release_1019c/x
KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
L=$(cygpath -w $ZR/start-server.ps1)
rm -rf slots225; mkdir -p slots225
SW="C:/bonsai/8gb/slots225"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
unset BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN BONSAI_SLOT_CACHE_EVERY
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p225_M -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
echo "$(date +%T) server M health $(curl -s localhost:8080/health) power $(nvidia-smi --query-gpu=power.limit --format=csv,noheader)" >> $R/run.txt
PYTHONUTF8=1 python p224_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $R/layer_M.log 2>&1 & LP=$!
for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done
for k in 1 2 3 4; do
  PYTHONUTF8=1 python p224_turn.py --key-file "$KEY" --depth 200000 --turn $k --arm M --state $R/state_M.json --short 2,4 --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt
done
for i in $(seq 1 300); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && break; sleep 2; done
kill $LP 2>/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; rm -rf slots225
grep -h "VRAM line" $(ls -t logs/*p225_M*.out.log | head -1) | head -2 >> $R/run.txt
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p225_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
python - "$(cygpath -w $R/turns.jsonl)" "$(cygpath -w receipts/p224/turns.jsonl)" >> $R/run.txt <<'PY'
import json, sys
m = {r['turn']: r for r in map(json.loads, open(sys.argv[1], encoding='utf-8'))}
d = {r['turn']: r for r in map(json.loads, open(sys.argv[2], encoding='utf-8')) if r['arm'] == 'D'}
same = 0
for t in sorted(m):
    eq = (m[t]['answer'] or '') == (d[t]['answer'] or '')
    same += eq
    print('turn', t, 'byte-equal' if eq else 'DIFFERENT', '| M:', (m[t]['answer'] or '').replace('\n', ' / ')[:120], '| D:', (d[t]['answer'] or '').replace('\n', ' / ')[:120], '| M wall', m[t]['wall_s'])
print('M = P224 D on', same, 'of', len(m), '(gate 4/4)')
PY
echo "$(date +%T) done" >> $R/run.txt
