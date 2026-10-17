#!/usr/bin/env bash
# P158d (#138, the kernel session's P158c arms 21:18Z + the POOL_LOG arm 23:35Z): the VMM pool-growth fix on the 2060.
# Engine product-0060p 4fcd19004 (= product-0060 incl. the draft sidecar + VMM growth retries + 16 MiB growth pieces +
# GGML_CUDA_POOL_RESERVE_MIB / GGML_CUDA_POOL_LOG), 75-real -> bin-0060p. Slot-save launcher copy, BONSAI_LAYER=0, defaults:
# MTP ON, shared pool ON. Method p157_restore.py; one fresh server per restore arm. (The "old" arm is P158 / P158c:
# product-slotdraft crashed 5/5 at 64k / 131k; with the shared pool on and no crash, 24.2 tok/s.)
#   prime64 (+ GGML_CUDA_POOL_LOG=1: the cold-read pool peak on sm_75) + save;
#   e_def x3 (defaults: pieces + retry, no reserve), e_res192 x2 (+ GGML_CUDA_POOL_RESERVE_MIB=192),
#   e_log (defaults + GGML_CUDA_POOL_LOG=1: does the pool grow far past ~170 MiB after a restore?);
#   prime131 + save, f_def x2 (defaults, 131k).
# Gates (as R1, declared before the run): the restore log says "draft context state restored"; new-token prompt eval >= 150
# tok/s at 64k and >= 100 tok/s at 131k; answers equal to the prime's continuation answer; 0 CUDA errors over all restores.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p158d; mkdir -p $R slots158d
S=/c/bonsai/bonsai-ada-surgery; BIN='C:/bonsai/bonsai-ada-surgery/bin-0060p'
grep -q 4fcd19004 <($S/bin-0060p/llama-server.exe --version 2>&1) || { echo "bin-0060p is not 4fcd19004" > $R/summary.txt; exit 1; }
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots158d'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p158d_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
grab() { E=$(ls -t logs/*p158d_$1*.err.log | head -1); { echo "== $1"; grep -hE "prompt eval time|CUDA error|draft context|growing|pool\[|POOL" "$E" | tail -12; echo "pool growth lines: $(grep -cE 'growing|pool\[' "$E")"; } >> $R/dbg.txt; }
run() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY "$@" >> $R/run.txt 2>&1; }
serve prime64 "$V;GGML_CUDA_POOL_LOG=1"; run --depth 65536 --phase prime --file a.bin --state $R/stateA.json --out $R/p158d.jsonl --tag prime64; grab prime64
for t in e_def1 e_def2 e_def3; do serve $t "$V"; run --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/p158d.jsonl --tag $t; grab $t; done
for t in e_res192a e_res192b; do serve $t "$V;GGML_CUDA_POOL_RESERVE_MIB=192"; run --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/p158d.jsonl --tag $t; grab $t; done
serve e_log "$V;GGML_CUDA_POOL_LOG=1"; run --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/p158d.jsonl --tag e_log; grab e_log
serve prime131 "$V"; run --depth 131072 --phase prime --file b.bin --state $R/stateB.json --out $R/p158d.jsonl --tag prime131; grab prime131
for t in f_def1 f_def2; do serve $t "$V"; run --depth 131072 --phase cont --new 4000 --file b.bin --state $R/stateB.json --out $R/p158d.jsonl --tag $t; grab $t; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -f slots158d/*
{ cut -c1-330 $R/p158d.jsonl; echo; echo "CUDA error lines: $(grep -c 'CUDA error' $R/dbg.txt)"; cat $R/dbg.txt; } > $R/summary.txt
