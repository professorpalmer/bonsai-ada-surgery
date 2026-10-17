#!/usr/bin/env bash
# P166b (spill guard G4b with a ballast that meets the guard's rule): P166's G4b used (free - 100) = 182 MiB on the 2060 (only
# 282 MiB free with the server up), below the guard's 512 MiB "other programs" rule, so no line; the 16k read still halved
# (198.7 tok/s). Here the ballast is 1,500 MiB (WDDM oversubscription: it pushes the server's memory out). Gate (declared before
# the run): the "spill" line within 45 s of the ballast. Report the 16k read speed and free VRAM. G4a is not repeated.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p166b; mkdir -p $R
BIN=$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-sgtest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
# G4b
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p166b_g4b -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p166b_g4b*.out.log | head -1); E="${O%.out.log}.err.log"
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=1500
T0=$(date +%s); echo "$(date +%T) free $FREE MiB, ballast $N MiB" >> $R/g4b.txt
python gpu_ballast.py $N $R/ballast.pid >> $R/g4b.txt 2>&1 &
sleep 45
echo "$(date +%T) after 45 s: free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB" >> $R/g4b.txt
grep -n '^spill' "$O" >> $R/g4b.txt; T1=$(date +%s)
PYTHONUTF8=1 python /c/bonsai/bonsai-ada-surgery/bench/quick_tps.py --base http://127.0.0.1:8080 --key-file $KEY --depth 16000 2>&1 | grep -E "depth|mean decode|rror" >> $R/g4b.txt
[ -f $R/ballast.pid ] && taskkill //PID $(cat $R/ballast.pid) //F >/dev/null 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ echo "== G4b"; cat $R/g4b.txt; echo "spill lines (all): $(grep -c '^spill' "$O")"; grep '^spill' "$O"; echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } > $R/summary.txt
