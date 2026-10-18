#!/usr/bin/env bash
# P184 (T5 window 32k in a P164-style agent soak): bin-t5r3 with LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024 via the
# 1017 launcher copy (BONSAI_BIN), slot save path, defaults otherwise; the serve-1017 layer (zip layer + #159) by p164_layer.py
# on :8081 with the cache on. Driver p155_turn.py as P164: a ~131k document, then ~4k tokens of tool output + a question per
# turn, 30 turns (to ~250k), thinking off, temp 0, server + layer restart before every 3rd turn.
# Gates (declared before the run): the P164 gates (30/30 answers, 0 one-token, 0 CUDA errors, restart turn wall <= 2x the
# median at that depth, trace min free >= 60 MiB); reported against P164 (dense): per-turn wall (model: ~44 -> ~15 s at 250k),
# and answers equal to P164 turn by turn.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p184; mkdir -p $R; rm -rf slots184; mkdir -p slots184
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
T5=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r3)
SW='C:/bonsai/8gb/slots184'; V="BONSAI_BIN=$T5;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW;LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024"
export BONSAI_SLOT_SAVE_PATH="$SW"
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/mem.txt & MP=$!
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p164_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p184_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
for k in $(seq 1 30); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then serve t$k; layer t$k; fi
  PYTHONUTF8=1 python p155_turn.py --key-file $KEY --depth 131072 --turn $k --arm S --state $R/state.json --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt
done
[ -n "$LP" ] && kill $LP 2>/dev/null; kill $MP
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots184
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
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p184_*.err.log 2>/dev/null | wc -l)" >> $R/summary.txt
grep -h "\[slots\]" $R/layer_*.log >> $R/summary.txt; cat $R/run.txt | grep -E "server|Error|error" >> $R/summary.txt

python - "$(cygpath -w $R/turns.jsonl)" "$(cygpath -w receipts/p164/turns.jsonl)" >> $R/summary.txt <<'PY2'
import json, sys
a = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[1], encoding='utf-8')}
b = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[2], encoding='utf-8')}
same = sum(1 for t in a if t in b and (a[t]['answer'] or '').strip() == (b[t]['answer'] or '').strip())
print('answers equal to P164:', same, 'of', len(a))
for t in sorted(a):
    if t in b: print('turn', t, 'wall', a[t]['wall_s'], 'vs P164', b[t]['wall_s'])
PY2
