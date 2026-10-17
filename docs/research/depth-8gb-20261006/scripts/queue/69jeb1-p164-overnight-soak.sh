#!/usr/bin/env bash
# P164 (overnight soak of what Cary serves): bundle-20261017 in C:/bonsai/serve-1017 (its own start-server.ps1 and bin; models
# linked), BONSAI_SLOT_SAVE_PATH, defaults (q3_0, auto sparse, MTP on, shared pool on), the serve folder's layer (zip layer +
# PR #159) run by p164_layer.py on :8081 with the cache on (sandbox stubbed). Driver p155_turn.py: an agent-like session that
# starts with a ~131k document and adds ~4k tokens of tool output + a question per turn, 30 turns (to ~250k), thinking off,
# temp 0. The server + layer restart before every 3rd turn (turns 4, 7, ... 28); the layer restores the session.
# Gates (declared before the run): all 30 turns answer (no HTTP error, no empty answer); 0 one-token answers; 0 CUDA errors in
# the server logs; after each restart the turn's wall <= 2x the median of the non-restart turns at that depth (+ any save);
# trace min free >= 60 MiB. Reported: per-turn wall, prompt_n, decode tok/s, the layer's restore / save lines.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p164; mkdir -p $R; rm -rf slots164; mkdir -p slots164
L='C:/bonsai/serve-1017/start-server.ps1'; KEY=C:/bonsai/serve-1017/artifacts/api_key.txt
SW='C:/bonsai/8gb/slots164'; V="BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW"
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/mem.txt & MP=$!
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p164_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p164_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
for k in $(seq 1 30); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file $KEY --depth 131072 --turn $k --arm S --state $R/state.json --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt
done
[ -n "$LP" ] && kill $LP 2>/dev/null; kill $MP
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots164
python - "$(cygpath -w $R/turns.jsonl)" > $R/summary.txt <<'PY'
import json, sys, statistics
rows = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
print('turn restart  wall_s  prompt_n  pred  tg  answer')
walls = [r['wall_s'] for r in rows if r['turn'] > 1 and (r['turn'] - 1) % 3 != 0]
med = statistics.median(walls) if walls else None
for r in rows:
    rs = r['turn'] > 1 and (r['turn'] - 1) % 3 == 0
    print(f"{r['turn']:>4} {str(rs):>7} {r['wall_s']:>7} {r['prompt_n']!s:>8} {r['predicted_n']!s:>5} {round(r['tg'] or 0, 1):>5}  {repr((r['answer'] or '')[:40])}")
print('turns', len(rows), 'empty answers', sum(1 for r in rows if not (r['answer'] or '').strip()), 'one-token', sum(1 for r in rows if r['predicted_n'] == 1), 'median non-restart wall', med)
PY
awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/mem.txt >> $R/summary.txt
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p164_*.err.log 2>/dev/null | wc -l)" >> $R/summary.txt
grep -h "\[slots\]" $R/layer_*.log >> $R/summary.txt; cat $R/run.txt | grep -E "server|Error|error" >> $R/summary.txt
