#!/usr/bin/env bash
# P162 (PR #159, #138 T1-d): read ahead on the 2060. Engine product-0060p 4fcd19004 (bin-0060p: sidecar + pool fix; the 0062
# candidate tree), MTP on, shared pool on (defaults); the slot-save launcher copy, BONSAI_LAYER=0 + the PR's layer run by
# p162_layer.py --cache on :8081 (frozen copy C:\bonsai\8gb\layer_ra; code sandbox stubbed). Driver p162_drive.py, streamed.
#   1. server + layer: read ahead [user: a ~131k document] ("prefill_only": true).
#   2. fresh server + fresh layer (a restart): ask [user: document], [user: question] -> the layer restores.
#   3. control: fresh server + layer with the cache OFF: the same ask, cold.
# Gates (declared before the run): 1 returns prefill_only with slot_cache_saved ~= the document's tokens; 2 restores, its wall
# <= 15 s, its answer == the control's answer; 0 CUDA errors in all server logs.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p162; mkdir -p $R; rm -rf slots162; mkdir -p slots162
S=/c/bonsai/bonsai-ada-surgery; BIN='C:/bonsai/bonsai-ada-surgery/bin-0060p'
grep -q 4fcd19004 <($S/bin-0060p/llama-server.exe --version 2>&1) || { echo "bin-0060p is not 4fcd19004" > $R/summary.txt; exit 1; }
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots162'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
export BONSAI_SLOT_SAVE_PATH="$SW"
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p162_layer.py --port 8081 --upstream http://127.0.0.1:8080 $2 > $R/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
serve() { [ -n "$LP" ] && kill $LP 2>/dev/null; LP=""
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p162_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
drive() { PYTHONUTF8=1 python p162_drive.py --key-file $KEY --depth 131072 --out $R/p162.jsonl "$@" >> $R/run.txt 2>&1; }
serve ra; layer ra --cache; drive --phase readahead --tag readahead
serve ask; layer ask --cache; drive --phase ask --tag ask_after_restart
serve cold; layer cold ""; drive --phase ask --tag ask_cold_control
[ -n "$LP" ] && kill $LP 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
ls -l slots162 > $R/slots.txt; rm -rf slots162
{ cut -c1-600 $R/p162.jsonl; echo; grep -h "\[slots\]" $R/layer_*.log; echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p162_*.err.log 2>/dev/null | wc -l)"; cat $R/slots.txt; } > $R/summary.txt
