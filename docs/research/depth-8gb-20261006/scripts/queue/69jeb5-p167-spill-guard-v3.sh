#!/usr/bin/env bash
# P167 (spill guard v3 c345b33 on the 2060, #138 07:55Z; gates declared there): launcher test copy (BONSAI_BIN line only) on the
# bundle-20261017 zip bins, defaults. Arms: G4b-v3 small ballast (free - 100 MiB) -> the "other programs took" line within 45 s;
# G4b-v3 1,500 MiB ballast -> the line within 45 s (P166b with v2: no line, then CUDA OOM on the next read); G4a-v3 cold 128k,
# no ballast -> 0 lines, TTFT within 2 % of P166 (530.8 s). Report the first-sample free VRAM, the read speed, CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p167; mkdir -p $R
BIN=$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-sg3test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
# G4b
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p167_small -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p167_small*.out.log | head -1); E="${O%.out.log}.err.log"
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=$((FREE - 100))
T0=$(date +%s); echo "$(date +%T) free $FREE MiB, ballast $N MiB" >> $R/small.txt
python gpu_ballast.py $N $R/ballast_small.pid >> $R/small.txt 2>&1 &
sleep 45
echo "$(date +%T) after 45 s: free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB" >> $R/small.txt
grep -n '^spill' "$O" >> $R/small.txt; T1=$(date +%s)
PYTHONUTF8=1 python /c/bonsai/bonsai-ada-surgery/bench/quick_tps.py --base http://127.0.0.1:8080 --key-file $KEY --depth 16000 2>&1 | grep -E "depth|mean decode|rror" >> $R/small.txt
[ -f $R/ballast_small.pid ] && taskkill //PID $(cat $R/ballast_small.pid) //F >/dev/null 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ echo "== G4b-v3 small (free - 100)"; cat $R/small.txt; echo "spill lines (all): $(grep -c '^spill' "$O")"; grep '^spill' "$O"; echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } >> $R/summary.txt

# G4b
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p167_big -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p167_big*.out.log | head -1); E="${O%.out.log}.err.log"
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=1500
T0=$(date +%s); echo "$(date +%T) free $FREE MiB, ballast $N MiB" >> $R/big.txt
python gpu_ballast.py $N $R/ballast_big.pid >> $R/big.txt 2>&1 &
sleep 45
echo "$(date +%T) after 45 s: free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB" >> $R/big.txt
grep -n '^spill' "$O" >> $R/big.txt; T1=$(date +%s)
PYTHONUTF8=1 python /c/bonsai/bonsai-ada-surgery/bench/quick_tps.py --base http://127.0.0.1:8080 --key-file $KEY --depth 16000 2>&1 | grep -E "depth|mean decode|rror" >> $R/big.txt
[ -f $R/ballast_big.pid ] && taskkill //PID $(cat $R/ballast_big.pid) //F >/dev/null 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ echo "== G4b-v3 1500 MiB"; cat $R/big.txt; echo "spill lines (all): $(grep -c '^spill' "$O")"; grep '^spill' "$O"; echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } >> $R/summary.txt

# G4a
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/g4a.mem.txt & MP=$!
bash run_arm.sh $R g4a "$V" "$L" "128000"; kill $MP
O=$(ls -t logs/*-g4a.out.log | head -1); E="${O%.out.log}.err.log"
{ echo "== G4a-v3"; grep -E "^code|mean decode|did not" $R/g4a.txt; echo "spill lines: $(grep -c '^spill' "$O")"; grep '^spill' "$O";
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/g4a.mem.txt
  echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } > $R/summary_g4a.txt
cat $R/summary_g4a.txt >> $R/summary.txt
