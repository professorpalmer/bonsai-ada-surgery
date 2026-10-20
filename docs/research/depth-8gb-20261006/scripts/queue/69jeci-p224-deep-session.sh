#!/usr/bin/env bash
# P224 (a deep-session check, Cary 2026-10-20 "do it all"): fresh 4k turns and a ~200k conversation across restarts on bundle-20261019c, the
# zip's own launcher with its defaults, the zip's layer with the saved-conversation cache (p224_layer.py: sandbox stubbed, as
# P211 / P220), GROW 4096 exported (the external layer does not inherit the launcher env, P204).
# Arm F (fresh agent job): a 4k facility document + 4 turns (each later turn: the answer, a ~2.5k-token tool output, a question),
#   one server, no restart.
# Arm D (the deep session): a ~200k document. D1 = the cold read + Q1. Restart (server + layer), D2 = a SHORT follow-up (no tool
#   block): the short turn. Restart, D3 = a tool output + Q3. D4 = a short Q4 on the same server (warm, no restore).
# Gate (declared before the run): D2 wall <= 15 s; D3 wall <= 60 s; D4 wall <= 15 s; every answer correct (graded against the
#   codes in the document: Q1 8/8 codes, Q2 the largest vault and code, Q3 the sum of vaults 1-3, Q4 the codes of vaults 5 and 7);
#   0 CUDA errors. Reported: every wall, prompt_n, decode, the layer slot events, VRAM lines.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p224; mkdir -p $R
ZR=release_1019c/x
KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
L=$(cygpath -w $ZR/start-server.ps1)
rm -rf slots224; mkdir -p slots224
SW="C:/bonsai/8gb/slots224"; V="BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
unset BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN BONSAI_SLOT_CACHE_EVERY
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p224_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 300); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done
  echo "$(date +%T) WARN layer still busy after 600 s" >> $R/run.txt; }
serve() { if [ -n "$LP" ]; then idle; ls -l slots224 > $R/slot_files_$1.txt; kill $LP 2>/dev/null; fi; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p224_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health) power $(nvidia-smi --query-gpu=power.limit --format=csv,noheader)" >> $R/run.txt; }
turn() { PYTHONUTF8=1 python p224_turn.py --key-file "$KEY" "$@" --out $R/turns.jsonl 2>&1 | tail -1 >> $R/run.txt; }
# Arm F
serve F; layer F
for k in 1 2 3 4; do turn --depth 4000 --turn $k --arm F --state $R/state_F.json; done
# Arm D
serve D1; layer D1
turn --depth 200000 --turn 1 --arm D --state $R/state_D.json --short 2,4
serve D2; layer D2
turn --depth 200000 --turn 2 --arm D --state $R/state_D.json --short 2,4
serve D3; layer D3
turn --depth 200000 --turn 3 --arm D --state $R/state_D.json --short 2,4
turn --depth 200000 --turn 4 --arm D --state $R/state_D.json --short 2,4
idle; ls -l slots224 > $R/slot_files_end.txt; [ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots224
grep -h "restored\|saved\|delta\|failed" $R/layer_*.log > $R/slot_events.txt
grep -h "VRAM line\|window\|spec " $(ls -t logs/*p224_D2*.out.log | head -1) | head -6 >> $R/run.txt
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p224_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
python - "$(cygpath -w $R/turns.jsonl)" >> $R/run.txt <<'PY'
import json, re, sys
for l in open(sys.argv[1], encoding='utf-8'):
    r = json.loads(l); c = r['codes']; a = r['answer'] or ''; t = r['turn']; nums = re.findall(r'\d+', a)
    if t == 1: ok = sum(1 for v, code in c.items() if re.search(r'vault\s*' + v + r'\D{0,4}' + code + r'\b', a, re.I)); g = '%d/8' % ok; good = ok == 8
    elif t == 2: v = max(c, key=lambda k: int(c[k])); good = v in nums and c[v] in nums; g = 'largest vault %s code %s' % (v, c[v])
    elif t == 3: s = str(sum(int(c[k]) for k in '123')); good = s in nums; g = 'sum %s' % s
    else: good = c['5'] in nums and c['7'] in nums; g = 'codes %s %s' % (c['5'], c['7'])
    lim = {('D', 2): 15, ('D', 3): 60, ('D', 4): 15}.get((r['arm'], t))
    w = '' if lim is None else (' wall gate <= %d s: %s' % (lim, 'PASS' if r['wall_s'] <= lim else 'FAIL'))
    print('%s t%d wall %s s prompt_n %s tg %s | %s: %s%s | %s' % (r['arm'], t, r['wall_s'], r['prompt_n'], r['tg'], g,
          'CORRECT' if good else 'WRONG', w, a.replace('\n', ' / ')[:160]))
PY
echo "$(date +%T) done" >> $R/run.txt
