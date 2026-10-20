#!/usr/bin/env bash
# P200 (G1 on the 2060, run beside the 4070's G1, #138 6248539701): the layer cache save step BONSAI_SLOT_CACHE_GROW 8192 (shipped)
# vs 4096, in one block, P164's 30-turn session (p155_turn.py: ~131k document, then ~4k tokens + a question per turn, thinking
# off), server + layer restarted before every 3rd turn, a fresh slot folder per arm. Bundle: C:/bonsai/serve-1017b (the 17b zip
# Cary serves) with its own launcher, BONSAI_SLOT_SAVE_PATH set, defaults; the layer = serve-1017 layer via p164_layer.py --cache.
# Gates (G1's, declared by the release session): with 4096, the mean restart-turn wall >= 25 % lower; the mean normal-turn wall
# at most 10 % higher; the session total lower; answers equal across arms on >= 28/30 turns; 0 CUDA errors.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p200; mkdir -p $R
L='C:/bonsai/serve-1017b/start-server.ps1'; KEY=C:/bonsai/serve-1017b/artifacts/api_key.txt
run_arm() {
G=$1; RA=$R/g$G; mkdir -p $RA; rm -rf slots200_$G; mkdir -p slots200_$G
SW="C:/bonsai/8gb/slots200_$G"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=$G
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $RA/mem.txt & MP=$!
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p164_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p200_g${G}_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $RA/run.txt; }
for k in $(seq 1 30); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file $KEY --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
[ -n "$LP" ] && kill $LP 2>/dev/null; kill $MP
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots200_$G
rm -rf slots200_$G
}
run_arm 8192
run_arm 4096
python - "$(cygpath -w $R)" > $R/summary.txt <<'PY2'
import json, os, statistics, sys
R = sys.argv[1]
rows = {g: [json.loads(l) for l in open(os.path.join(R, 'g' + g, 'turns.jsonl'), encoding='utf-8')] for g in ('8192', '4096')}
def split(rs):
    rst = [r['wall_s'] for r in rs if r['turn'] > 1 and (r['turn'] - 1) % 3 == 0]
    nrm = [r['wall_s'] for r in rs if r['turn'] > 1 and (r['turn'] - 1) % 3 != 0]
    return rst, nrm, sum(r['wall_s'] for r in rs)
for g, rs in rows.items():
    rst, nrm, tot = split(rs)
    print(g, 'turns', len(rs), 'restart mean', round(statistics.mean(rst), 1), 'normal mean', round(statistics.mean(nrm), 1), 'total', round(tot))
a, b = rows['8192'], rows['4096']
same = sum(1 for x, y in zip(a, b) if (x['answer'] or '').strip() == (y['answer'] or '').strip())
ra, na, ta = split(a); rb, nb, tb = split(b)
print('restart mean change', round(100 * (statistics.mean(rb) / statistics.mean(ra) - 1), 1), '% (gate <= -25)')
print('normal mean change', round(100 * (statistics.mean(nb) / statistics.mean(na) - 1), 1), '% (gate <= +10)')
print('total change', round(100 * (tb / ta - 1), 1), '% (gate < 0); answers equal', same, 'of', len(a), '(gate >= 28)')
PY2
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p200_*.err.log 2>/dev/null | wc -l)" >> $R/summary.txt
grep -h "\[slots\]" $R/g*/layer_*.log | tail -20 >> $R/summary.txt
