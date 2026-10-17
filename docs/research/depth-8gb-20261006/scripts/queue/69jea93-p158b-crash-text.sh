#!/usr/bin/env bash
# P158b (debug, after P158 FAIL): get the full CUDA error text of the restore + continue crash on sm_75. bin-t3dbg = t3-prefill
# 0f7a8e0ce (sidecar server code, T3 off by default) + a local-only fprintf(stderr)+fflush in ggml_cuda_error (the server log
# is asynchronous and the abort loses the "CUDA error: ... in function ..." lines). Not for upstream.
# Prime 65,536 (MTP on) + save; then fresh-server restores + ~4k new tokens: x_def (defaults), x_blocking
# (GGML_CUDA_LAUNCH_BLOCKING=1: the failing kernel, not a later sync), x_nodraft_blocking (the .draft moved aside).
# Reading: the P158DBG lines (error text, function, file:line, statement) per arm.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p158b; mkdir -p $R slots158b
BIN='C:/bonsai/bonsai-ada-surgery/bin-t3dbg'
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots158b'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p158b_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
grab() { E=$(ls -t logs/*p158b_$1*.err.log | head -1); O="${E%.err.log}.out.log"; { echo "== $1"; grep -hE "P158DBG|CUDA error|draft context|prompt eval" "$E" "$O" | tail -8; } >> $R/dbg.txt; }
run() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY --depth 65536 --file x.bin --state $R/state.json --out $R/p158b.jsonl "$@" >> $R/run.txt 2>&1; }
serve prime "$V"; run --phase prime --tag prime; grab prime
serve x_def "$V"; run --phase cont --new 4000 --tag x_def; grab x_def
serve x_blocking "$V;GGML_CUDA_LAUNCH_BLOCKING=1"; run --phase cont --new 4000 --tag x_blocking; grab x_blocking
mv slots158b/x.bin.draft slots158b/x.bin.draft.aside 2>/dev/null
serve x_nodraft_blocking "$V;GGML_CUDA_LAUNCH_BLOCKING=1"; run --phase cont --new 4000 --tag x_nodraft_blocking; grab x_nodraft_blocking
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -f slots158b/x.bin*
{ cut -c1-300 $R/p158b.jsonl; echo; cat $R/dbg.txt; } > $R/summary.txt
