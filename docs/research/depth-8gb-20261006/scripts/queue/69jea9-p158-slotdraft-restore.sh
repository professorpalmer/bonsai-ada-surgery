#!/usr/bin/env bash
# P158 (#138 T1-h ask, 4070 16:44Z): slot restore + MTP on the 2060 with the draft-context sidecar. Engine product-slotdraft
# 303f01131 (= 0059 + "slot save / restore also save / restore the draft context in a <file>.draft sidecar" + the fix that
# really loads it), 75-real -> bin-slotdraft. The slot-save launcher test copy, BONSAI_LAYER=0, defaults (MTP on, lookup on).
# Method: p157_restore.py (P157 / P157b). One fresh server per arm; the prime server saves <file>.bin + <file>.draft.
#   A 65,536: prime; s_def, s_def2 (restore with the sidecar, ~4k new tokens); s_nodraft (the .draft moved aside first);
#     s_nomtp (BONSAI_SPEC=0, control = P157b d_nomtp 212.6 tok/s).
#   B 131,072: prime; b_def, b_def2 (restore with the sidecar, ~4k new tokens).
# Gates (declared before the run): G1 the save writes a .draft file and the restore log says "draft context state restored";
#   G2 prompt eval of the new tokens after a fresh restore >= 150 tok/s at 64k (P157b MTP on: 24.0; off: 212.6) and >= 100
#   tok/s at 131k (P157: 12.2; in the same process: ~132); G3 answers equal to the s_nomtp / prime-continuation answers;
#   G4 0 "CUDA error" in all server logs. s_nodraft is reported (the 4070: the draft sequence is cleared; speed unknown here).
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p158; mkdir -p $R slots158
S=/c/bonsai/bonsai-ada-surgery; BIN='C:/bonsai/bonsai-ada-surgery/bin-slotdraft'
grep -q 303f01131 <($S/bin-slotdraft/llama-server.exe --version 2>&1) || { echo "bin-slotdraft is not 303f01131" > $R/summary.txt; exit 1; }
L='C:/bonsai/bonsai-ada-surgery/start-server-slottest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
SW='C:\bonsai\8gb\slots158'; V="BONSAI_BIN=$BIN;BONSAI_LAYER=0;BONSAI_SLOT_SAVE_PATH=$SW"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p158_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  echo "$(date +%T) $1 health $(curl -s localhost:8080/health)" >> $R/run.txt; }
grab() { E=$(ls -t logs/*p158_$1*.err.log | head -1); { echo "== $1 ($E)"; grep -E "prompt eval time|CUDA error|draft context|sidecar" "$E" | tail -6; } >> $R/errtails.txt
  echo "$(date +%T) $1 health after: $(curl -s -m 3 localhost:8080/health)" >> $R/run.txt; }
run() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY "$@" >> $R/run.txt 2>&1; }
# A: 64k
serve primeA "$V"; run --depth 65536 --phase prime --file a.bin --state $R/stateA.json --out $R/p158.jsonl --tag primeA; grab primeA
ls -l slots158 >> $R/run.txt
for t in s_def s_def2; do serve $t "$V"; run --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/p158.jsonl --tag $t; grab $t; done
mv slots158/a.bin.draft slots158/a.bin.draft.aside 2>/dev/null
serve s_nodraft "$V"; run --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/p158.jsonl --tag s_nodraft; grab s_nodraft
mv slots158/a.bin.draft.aside slots158/a.bin.draft 2>/dev/null
serve s_nomtp "$V;BONSAI_SPEC=0;BONSAI_CTX=262144"; run --depth 65536 --phase cont --new 4000 --file a.bin --state $R/stateA.json --out $R/p158.jsonl --tag s_nomtp; grab s_nomtp
# B: 131k
serve primeB "$V"; run --depth 131072 --phase prime --file b.bin --state $R/stateB.json --out $R/p158.jsonl --tag primeB; grab primeB
for t in b_def b_def2; do serve $t "$V"; run --depth 131072 --phase cont --new 4000 --file b.bin --state $R/stateB.json --out $R/p158.jsonl --tag $t; grab $t; done
ls -l slots158 >> $R/run.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -f slots158/*.bin slots158/*.draft
{ cut -c1-400 $R/p158.jsonl; echo; echo "CUDA error lines: $(cat $R/errtails.txt | grep -c 'CUDA error')"; cat $R/errtails.txt; echo; cat $R/run.txt; } > $R/summary.txt
