#!/usr/bin/env bash
# P212 (the 2060 reference for P211): the same 12 turns of the P164 session on the bundle-20261018f zip's own launcher, the 18f
# layer via p211_layer.py WITHOUT --cache (no saves, no restores), one server for all 12 turns (no restarts). The 4070's 18f gate
# is "answers equal to cache-off"; this gives the 2060's cache-off answers. Report: P211 (cache on, restarts) vs this, turn by
# turn (gate for 18f's claim: 12/12).
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p212; mkdir -p $R
ZR=release_1018f/x
KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
L=$(cygpath -w $ZR/start-server.ps1)
unset BONSAI_SLOT_SAVE_PATH BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN BONSAI_SLOT_CACHE_EVERY BONSAI_SLOT_CACHE_GROW
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p212_ref -Launcher "$L" -Vars "" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
PYTHONUTF8=1 python p211_layer.py --port 8081 --upstream http://127.0.0.1:8080 > $R/layer.log 2>&1 & LP=$!
for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done
for k in $(seq 1 12); do
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $R/state.json --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt
done
kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - "$(cygpath -w $R/turns.jsonl)" "$(cygpath -w receipts/p211/arm/turns.jsonl)" "$(cygpath -w receipts/p205/after1/turns.jsonl)" >> $R/run.txt <<'PY'
import json, sys
ref = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[1], encoding='utf-8')}
for name, p in (('P211 (18f, cache on, restarts)', sys.argv[2]), ('P205 (18 + after, restarts)', sys.argv[3])):
    rows = [json.loads(l) for l in open(p, encoding='utf-8')][:12]
    same = [r['turn'] for r in rows if (r['answer'] or '').strip() == (ref[r['turn']]['answer'] or '').strip()]
    print(name, 'equal to cache-off on', len(same), 'of', len(rows), '; differ at', [r['turn'] for r in rows if r['turn'] not in same])
PY
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p212_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
