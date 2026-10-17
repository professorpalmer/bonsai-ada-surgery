#!/usr/bin/env bash
# P157b (after P155b, written 09:47 before any P157 result): is the restore + continue crash / slowdown the MTP draft context?
# P155b crashed after a restore at 64k (below the VRAM line) too, and read the new tokens at ~12 tok/s after a restore at 131k
# (~133 in memory). Guess: the slot file holds the main context only; the MTP draft context (and the lookup n-gram state)
# start empty after a restore. bundle-20261016 zip bins + the slot-save launcher copy, BONSAI_LAYER=0, ctx 262144.
# Prime once at 65,536 (cold ~4 min), save; one fresh server per arm, restore, continue with ~4k new tokens:
#   d_def (defaults), d_nomtp (BONSAI_SPEC=0; BONSAI_CTX=262144), d_nolookup (BONSAI_LOOKUP=0), d_none (both off),
#   d_def2 (defaults again).
# Reading (declared before the run): crash or not per arm, prompt eval tok/s of the new tokens, answer vs d_none.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p157b; mkdir -p $R slots157b
BIN=$(cd "$(dirname "$(find release_1016/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots157b'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p157b_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
grab() { E=$(ls -t logs/*p157b_$1*.err.log | head -1); { echo "== $1 ($E)"; grep -E "prompt eval time|CUDA error|spec|draft" "$E" | tail -6; } >> $R/errtails.txt; echo "$(date +%T) $1 health after: $(curl -s -m 3 localhost:8080/health)" >> $R/run.txt; }
run() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY --depth 65536 --file p157b.bin --state $R/state.json --out $R/p157b.jsonl "$@" >> $R/run.txt 2>&1; }
serve prime "$V"; run --phase prime --tag prime; grab prime
serve d_def "$V"; run --phase cont --new 4000 --tag d_def; grab d_def
serve d_nomtp "$V;BONSAI_SPEC=0;BONSAI_CTX=262144"; run --phase cont --new 4000 --tag d_nomtp; grab d_nomtp
serve d_nolookup "$V;BONSAI_LOOKUP=0"; run --phase cont --new 4000 --tag d_nolookup; grab d_nolookup
serve d_none "$V;BONSAI_SPEC=0;BONSAI_CTX=262144;BONSAI_LOOKUP=0"; run --phase cont --new 4000 --tag d_none; grab d_none
serve d_def2 "$V"; run --phase cont --new 4000 --tag d_def2; grab d_def2
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -f slots157b/p157b.bin
{ cut -c1-400 $R/p157b.jsonl; echo; cat $R/run.txt; echo; cat $R/errtails.txt; } > $R/summary.txt
