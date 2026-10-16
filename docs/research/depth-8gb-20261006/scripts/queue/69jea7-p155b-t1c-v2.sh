#!/usr/bin/env bash
# P155b (#138 T1-c v2, after the 4070 review 11:33Z): the same arms and gates as P155, with the layer's save point moved
# BEFORE the generation prompt (tokens of the template output with add_generation_prompt false; the next turn renders the
# previous answer from the history, so the generation-prompt tokens can differ, most of all with thinking on), and the
# saved token count taken from the server's n_saved. Layer copy: C:\bonsai\8gb\layer_v2 (p155b_layer.py).
# Extra gates (4070 review, declared before the run): the save's n_saved == the prefill token count (slot_events: "saved N");
# after a restore, prompt_n of the turn <= the new tokens of the turn + the generation prompt + 512. The thinking-on pair
# (RT turns 2-3) is now GATED the same way (it is the case v2 fixes).
# Arms (temp 0):
#   M   memory: one server + layer, cache OFF, turns 1-5 at 131,072 (think off), then the edited-history request (turn 3 --edit).
#   R   restart: before EVERY turn a fresh server + a fresh layer, cache ON (one folder, empty at the start), turns 1-5,
#       then the edited request on a fresh server + layer.
#   S   short prompt: 4,000-token turn 1, layer cache off vs on, the same server.
#   MT / RT  thinking on (max_tokens 1024), 65,536, turns 1-3: memory vs restart + cache.
# Gates (declared before the run):
#   E1 R answers == M answers byte for byte at every turn; R turns 2-5: prompt_n <= new tokens of the turn + 512.
#   E3 the edited request: no restore for it (no saved file is a prefix of it; slot_events.txt shows no 'restored' in the
#      Redit layer log), the whole prompt is read again (in the layer's prefill-only call: wall_s ~ a cold 128k read),
#      and its answer == M's edited answer.
#   S  the 4k answers byte-identical; no restore and no save at 4k.
#   Thinking on: RT turns 2-3 prompt_n <= new tokens + 512 (reported against MT; answers compared, not gated).
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p155b; mkdir -p $R; rm -rf slots155b; mkdir -p slots155b
BIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots155b'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW"
LP=""
layer() {   # $1 tag, $2 cache flag ("" or --cache)
  [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p155b_layer.py --port 8081 --upstream http://127.0.0.1:8080 $2 > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p155b_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
turn() { PYTHONUTF8=1 python p155_turn.py --key-file $KEY "$@" --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt; }
D=131072
# M
serve M; layer M ""
for k in 1 2 3 4 5; do turn --depth $D --turn $k --arm M --state $R/state_M.json; done
turn --depth $D --turn 3 --arm M --state $R/state_M.json --edit
# R
for k in 1 2 3 4 5; do serve R$k; layer R$k --cache; turn --depth $D --turn $k --arm R --state $R/state_R.json; done
serve Redit; layer Redit --cache; turn --depth $D --turn 3 --arm R --state $R/state_R.json --edit
ls -l slots155b > $R/slots_after_R.txt
# S
serve S; layer S0 ""; turn --depth 4000 --turn 1 --arm S0 --state $R/state_S0.json
layer S1 --cache; turn --depth 4000 --turn 1 --arm S1 --state $R/state_S1.json
# thinking on
serve MT; layer MT ""
for k in 1 2 3; do turn --depth 65536 --turn $k --arm MT --state $R/state_MT.json --think; done
for k in 1 2 3; do serve RT$k; layer RT$k --cache; turn --depth 65536 --turn $k --arm RT --state $R/state_RT.json --think; done
[ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
grep -h "\[slots\]" $R/layer_*.log > $R/slot_events.txt
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
cat $R/slot_events.txt >> $R/summary.txt; cat $R/run.txt >> $R/summary.txt
