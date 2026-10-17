#!/usr/bin/env bash
# P166 (spill guard G4 on the 2060, #138 07:28Z; gates declared there): bundle-20261017 zip bins (release_1017) + start-server.ps1
# from branch spill-guard 5edcfe7 as a test copy (only the BONSAI_BIN line added), defaults (q3_0, line ~80.6k, sparse auto,
# layer off).
#   G4a: a cold 128k read + a 400-token decode (run_arm / quick_tps --depth 128000), 10 s VRAM trace. PASS: 0 "spill" lines in
#        the launcher output; TTFT within 2 % of P163 (529.3 s). Report the trace min free.
#   G4b: fresh server; after /health a CUDA ballast of (free VRAM - 100) MiB (gpu_ballast.py, torch, touched); wait 45 s; then a
#        cold 16k read. PASS: the line "spill  other programs took ... MiB of VRAM after the start and the card is full" in the
#        launcher output within 45 s of the ballast. Report the 16k read speed. Stop the ballast by PID.
#   Both: 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p166; mkdir -p $R
BIN=$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-sgtest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
# G4a
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/g4a.mem.txt & MP=$!
bash run_arm.sh $R g4a "$V" "$L" "128000"; kill $MP
O=$(ls -t logs/*-g4a.out.log | head -1); E="${O%.out.log}.err.log"
{ echo "== G4a"; grep -E "^code|mean decode|did not" $R/g4a.txt; echo "spill lines: $(grep -c '^spill' "$O")"; grep '^spill' "$O";
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/g4a.mem.txt
  echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } > $R/summary.txt
# G4b
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p166_g4b -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p166_g4b*.out.log | head -1); E="${O%.out.log}.err.log"
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=$((FREE - 100))
T0=$(date +%s); echo "$(date +%T) free $FREE MiB, ballast $N MiB" >> $R/g4b.txt
python gpu_ballast.py $N $R/ballast.pid >> $R/g4b.txt 2>&1 &
sleep 45
echo "$(date +%T) after 45 s: free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB" >> $R/g4b.txt
grep -n '^spill' "$O" >> $R/g4b.txt; T1=$(date +%s)
PYTHONUTF8=1 python /c/bonsai/bonsai-ada-surgery/bench/quick_tps.py --base http://127.0.0.1:8080 --key-file $KEY --depth 16000 2>&1 | grep -E "depth|mean decode|rror" >> $R/g4b.txt
[ -f $R/ballast.pid ] && taskkill //PID $(cat $R/ballast.pid) //F >/dev/null 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ echo "== G4b"; cat $R/g4b.txt; echo "spill lines (all): $(grep -c '^spill' "$O")"; grep '^spill' "$O"; echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } >> $R/summary.txt
