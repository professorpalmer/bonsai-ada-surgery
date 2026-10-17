#!/usr/bin/env bash
# P160 (#138 T1 with the P158c workaround): saved conversations on 8 GB with MTP ON and BONSAI_SHARED_POOL=0.
# Part A: the shipped bundle-20261016 zip bins + pool off: prime 64k + save, fresh restore + ~4k new tokens (p157_restore.py).
# Part B: the layer cache v2 (layer_v2 via p155b_layer.py) with bin-slotdraft (303f01131: the draft sidecar) + pool off: the P155b
#   arms: M (memory) vs R (restart before every turn) at 131,072, turns 1-5 + the edited request; 4k short check; MT vs RT
#   (thinking on) at 65,536, turns 1-3.
# Part C: a 200k resume (the demo clip): bin-slotdraft + pool off, prime ~200,000 (cold) + save, fresh restore + a short question
#   (~33 new tokens) and, on another fresh server, + ~4k new tokens: TTFT and wall.
# Gates (declared before the run): A: new-token prompt eval >= 150 tok/s, 0 CUDA errors. B: as P155b (R == M answers byte for
#   byte; after a restore prompt_n <= new tokens + generation prompt + 512; RT the same, gated; E3 no restore; 4k unchanged) and
#   0 CUDA errors. C: restore + short question wall <= 15 s; 0 CUDA errors. Reported: the VRAM lines, per-turn wall times.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p160; mkdir -p $R; rm -rf slots160; mkdir -p slots160
BIN='C:/bonsai/bonsai-ada-surgery/bin-slotdraft'; ZBIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots160'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW;BONSAI_SHARED_POOL=0"
export BONSAI_SLOT_SAVE_PATH="$SW"
LP=""
layer() {   # $1 tag, $2 cache flag ("" or --cache)
  [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p155b_layer.py --port 8081 --upstream http://127.0.0.1:8080 $2 > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p160_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
turn() { PYTHONUTF8=1 python p155_turn.py --key-file $KEY "$@" --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt; }
# Part A
runr() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY "$@" >> $R/partAC.txt 2>&1; }
VA="BONSAI_BIN=$ZBIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW;BONSAI_SHARED_POOL=0"
serve Aprime "$VA"; runr --depth 65536 --phase prime --file a.bin --state $R/stateA.json --out $R/partAC.jsonl --tag Aprime
serve Acont "$VA"; runr --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/partAC.jsonl --tag Acont
rm -f slots160/a.bin*
D=131072
# M
serve M; layer M ""
for k in 1 2 3 4 5; do turn --depth $D --turn $k --arm M --state $R/state_M.json; done
turn --depth $D --turn 3 --arm M --state $R/state_M.json --edit
# R
for k in 1 2 3 4 5; do serve R$k; layer R$k --cache; turn --depth $D --turn $k --arm R --state $R/state_R.json; done
serve Redit; layer Redit --cache; turn --depth $D --turn 3 --arm R --state $R/state_R.json --edit
ls -l slots160 > $R/slots_after_R.txt
# S
serve S; layer S0 ""; turn --depth 4000 --turn 1 --arm S0 --state $R/state_S0.json
layer S1 --cache; turn --depth 4000 --turn 1 --arm S1 --state $R/state_S1.json
# thinking on
serve MT; layer MT ""
for k in 1 2 3; do turn --depth 65536 --turn $k --arm MT --state $R/state_MT.json --think; done
for k in 1 2 3; do serve RT$k; layer RT$k --cache; turn --depth 65536 --turn $k --arm RT --state $R/state_RT.json --think; done
# Part C
serve Cprime "$V"; runr --depth 200000 --phase prime --file c.bin --state $R/stateC.json --out $R/partAC.jsonl --tag Cprime
serve Cshort "$V"; runr --depth 200000 --phase cont --new 33 --file c.bin --state $R/stateC.json --out $R/partAC.jsonl --tag Cshort
serve C4k "$V"; runr --depth 200000 --phase cont --new 4000 --file c.bin --state $R/stateC.json --out $R/partAC.jsonl --tag C4k
ls -l slots160 >> $R/run.txt; rm -f slots160/c.bin*
[ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
grep -h "\[slots\]" $R/layer_*.log > $R/slot_events.txt; grep -l "CUDA error" logs/*p160_*.err.log > $R/cuda_errors.txt 2>/dev/null; echo "CUDA error logs: $(wc -l < $R/cuda_errors.txt)" >> $R/run.txt
python - "$(cygpath -w $R/turns.jsonl)" > $R/summary.txt <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
get = lambda arm, turn, edit=False: next((r for r in rows if r['arm'] == arm and r['turn'] == turn and r['edit'] == edit), None)
print('arm turn edit  wall_s  prompt_n  predicted_n  tg')
for r in rows:
    print(f"{r['arm']:>3} {r['turn']:>4} {str(r['edit']):>5} {r['wall_s']:>7} {r['prompt_n']!s:>9} {r['predicted_n']!s:>12} {r['tg']}")
for a, b, turns in (('M', 'R', range(1, 6)), ('MT', 'RT', range(1, 4))):
    for k in turns:
        x, y = get(a, k), get(b, k)
        if x and y:
            print(f"{a} vs {b} turn {k}: answer equal {x['answer'] == y['answer']}; prompt_n {x['prompt_n']} vs {y['prompt_n']}; wall {x['wall_s']} vs {y['wall_s']} s")
x, y = get('M', 3, True), get('R', 3, True)
if x and y: print(f"E3 edited: answer equal {x['answer'] == y['answer']}; prompt_n M {x['prompt_n']} R {y['prompt_n']}; wall M {x['wall_s']} R {y['wall_s']} s")
x, y = get('S0', 1), get('S1', 1)
if x and y: print(f"S 4k: answer equal {x['answer'] == y['answer']}; wall {x['wall_s']} vs {y['wall_s']} s")
PY
cut -c1-300 $R/partAC.jsonl >> $R/summary.txt; cat $R/slot_events.txt >> $R/summary.txt; cat $R/run.txt >> $R/summary.txt
