#!/usr/bin/env bash
# P157 (repro for #138 T1; found in P155 R2): after a slot restore at 131k (past the VRAM line, host tail in use), a turn
# with ~4k new tokens crashed the server: "ggml-cuda.cu:109: CUDA error" right after "attention reads the host tail ...:
# CUDA graphs off, tier prefetch pipeline on" and the GDN line. P153 continued restored states with 33 new tokens with no
# error (64k / 131k / 245k). bundle-20261016 zip bins + the slot-save launcher test copy, BONSAI_LAYER=0.
# Prime once at 131,072 (cold, ~10 min), save; then one fresh server per arm, restore, continue with N new tokens:
#   c33 (~33 tokens, control = P153), c600 (~600, just over one ubatch), c4k (~4k, the P155 case), c4k_nosparse
#   (BONSAI_SPARSE=0), c4k_again (repeat of c4k), m4k (no restore: the same 4k continuation on the prime server, before save
#   ... run first, on the prime server, as the in-memory control).
# Reading (declared before the run): which arms crash; the server err-log tail of each crash (GGML_CUDA_LAUNCH_BLOCKING=1 on
# the crash arms for the failing op); whether sparse off changes it. No fix here; the report goes to the 4070 on #138.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p157; mkdir -p $R slots157
BIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots157'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p157_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
grab() { E=$(ls -t logs/*p157_$1*.err.log | head -1); { echo "== $1 ($E)"; tail -12 "$E"; } >> $R/errtails.txt; echo "$(date +%T) $1 health after: $(curl -s -m 3 localhost:8080/health)" >> $R/run.txt; }
run() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY --depth 131072 --file p157.bin --state $R/state.json --out $R/p157.jsonl "$@" >> $R/run.txt 2>&1; }
serve prime "$V"; run --phase prime --tag prime
# in-memory control on the same server: restore is a no-op here (the slot already holds it); it measures the 4k continuation
run --phase cont --new 4000 --tag m4k; grab prime
serve c33 "$V"; run --phase cont --new 33 --tag c33; grab c33
serve c600 "$V"; run --phase cont --new 600 --tag c600; grab c600
serve c4k "$V;GGML_CUDA_LAUNCH_BLOCKING=1"; run --phase cont --new 4000 --tag c4k; grab c4k
serve c4kns "$V;BONSAI_SPARSE=0;GGML_CUDA_LAUNCH_BLOCKING=1"; run --phase cont --new 4000 --tag c4k_nosparse; grab c4kns
serve c4k2 "$V"; run --phase cont --new 4000 --tag c4k_again; grab c4k2
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -f slots157/p157.bin
{ cut -c1-400 $R/p157.jsonl; echo; cat $R/run.txt; echo; cat $R/errtails.txt; } > $R/summary.txt
