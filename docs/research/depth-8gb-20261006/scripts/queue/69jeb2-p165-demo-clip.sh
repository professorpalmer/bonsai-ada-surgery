#!/usr/bin/env bash
# P165 (the demo clip on what Cary serves): serve-1017 (bundle-20261017 + the #159 layer via p164_layer.py, cache on), defaults
# (MTP on, shared pool on). Driver p165_drive.py, streamed, first-token time measured at the client.
#   1. read ahead [user: a ~200k document] ("prefill_only": true)  -> the one-time cold read
#   2. restart (fresh server + layer); ask Q1 as a new message      -> the restore + a short question
#   3. same server: Q2 (Q1 + answer + Q2), then Q3                 -> follow-ups in memory
#   4. restart again; ask Q3's history once more                    -> a second restore, deeper
# Gates (declared before the run): read-ahead status "saved"; step 2 first token <= 10 s, wall <= 30 s; steps 3 first token
# <= 10 s each; step 4 first token <= 10 s; answers non-empty; 0 CUDA errors. Reported: all times, answers, the layer lines.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p165; mkdir -p $R; rm -rf slots165; mkdir -p slots165
L='C:/bonsai/serve-1017/start-server.ps1'; KEY=C:/bonsai/serve-1017/artifacts/api_key.txt
SW='C:/bonsai/8gb/slots165'; V="BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW"
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p164_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p165_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) server $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
d() { PYTHONUTF8=1 python p165_drive.py --key-file $KEY --depth 200000 --state $R/state.json --out $R/clip.jsonl "$@" >> $R/run.txt 2>&1; }
serve ra; layer ra; d --phase readahead --tag readahead
serve q1; layer q1; d --phase ask --n 1 --tag q1_after_restart
d --phase ask --n 2 --tag q2_same_server
d --phase ask --n 3 --tag q3_same_server
serve q3r; layer q3r; d --phase ask --n 3 --tag q3_after_restart
[ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
ls -l slots165 > $R/slots.txt; rm -rf slots165
{ python -c "
import json
for l in open(r'C:/bonsai/8gb/receipts/p165/clip.jsonl'):
    r=json.loads(l); print(r['tag'], 'first_token', r.get('first_token_s'), 'wall', r.get('wall_s'), 'prompt_n', r.get('prompt_n'), 'tg', r.get('tg'), 'err', r.get('error'), 'status', (r.get('slot_cache') or {}).get('status'), '|', repr((r.get('answer') or '')[:80]))
"; grep -h "\[slots\]" $R/layer_*.log; echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p165_*.err.log 2>/dev/null | wc -l)"; cat $R/slots.txt; } > $R/summary.txt
