#!/usr/bin/env bash
# P203 (soak of Afterburner slot 3 = 215 W + core +100 after P202's +5-6 % prefill): P200's 8192 arm replayed on slot 3; the
# reference = P200 g8192 (stock, the same bundle and session). The card ends on slot 5. P164's 30-turn session (p155_turn.py: ~131k document, then ~4k tokens + a question per turn, thinking
# off), server + layer restarted before every 3rd turn, a fresh slot folder per arm. Bundle: C:/bonsai/serve-1017b (the 17b zip
# Cary serves) with its own launcher, BONSAI_SLOT_SAVE_PATH set, defaults; the layer = serve-1017 layer via p164_layer.py --cache.
# Gates (G1's, declared by the release session): with 4096, the mean restart-turn wall >= 25 % lower; the mean normal-turn wall
# at most 10 % higher; the session total lower; answers equal across arms on >= 28/30 turns; 0 CUDA errors.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p203; mkdir -p $R
L='C:/bonsai/serve-1017b/start-server.ps1'; KEY=C:/bonsai/serve-1017b/artifacts/api_key.txt
run_arm() {
G=$1; RA=$R/g$G; mkdir -p $RA; rm -rf slots203_$G; mkdir -p slots203_$G
SW="C:/bonsai/8gb/slots203_$G"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=$G
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free,temperature.gpu,clocks.sm,power.draw --format=csv,noheader,nounits)"; sleep 10; done ) > $RA/mem.txt & MP=$!
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p164_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 6; echo "$(date +%T) $1 applied: $(nvidia-smi --query-gpu=power.limit --format=csv,noheader)" >> $RA/run.txt
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p203_g${G}_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $RA/run.txt; }
for k in $(seq 1 30); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file $KEY --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
[ -n "$LP" ] && kill $LP 2>/dev/null; kill $MP
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots203_$G
rm -rf slots203_$G
}
trap 'powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null' EXIT
run_arm 8192
python - "$(cygpath -w $R)" "$(cygpath -w receipts/p200)" > $R/summary.txt <<'PY2'
import json, os, statistics, sys
a = [json.loads(l) for l in open(os.path.join(sys.argv[1], 'g8192', 'turns.jsonl'), encoding='utf-8')]
b = [json.loads(l) for l in open(os.path.join(sys.argv[2], 'g8192', 'turns.jsonl'), encoding='utf-8')]
same = sum(1 for x, y in zip(a, b) if (x['answer'] or '').strip() == (y['answer'] or '').strip())
print('turns', len(a), 'answers equal to P200 stock', same, 'of', len(b), '(gate 30/30)')
print('total', round(sum(r['wall_s'] for r in a)), 's vs P200 stock', round(sum(r['wall_s'] for r in b)), 's')
t = [float(l.split()[1].split(',')[1]) for l in open(os.path.join(sys.argv[1], 'g8192', 'mem.txt')) if l.count(',') >= 3]
print('temp max', max(t), 'C (gate < 85)')
PY2
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p203_*.err.log 2>/dev/null | wc -l)" >> $R/summary.txt
