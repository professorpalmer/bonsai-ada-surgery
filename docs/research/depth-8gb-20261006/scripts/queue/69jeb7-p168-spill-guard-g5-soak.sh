#!/usr/bin/env bash
# P168 (spill guard v5 7e4ac46, G5 soak, #138 08:50Z; gates declared there): bundle-20261017 zip bins (BONSAI_BIN in Windows
# form) + the 7e4ac46 launcher test copy, defaults; the display is on the 2060. A browser plays a video on the same card for the
# hour: Edge (its own profile in g5video\edgeprof) with g5.html = a looping 1080p VP8 clip made locally with OpenCV + a WebGL
# shader animation; started 30 s before the server. Reads: a cold 128k at the start, a cold 64k at ~15 / 30 / 45 min (a unique
# first line each, so no prompt-cache reuse), 3 short requests after each 64k; then a (free - 100) MiB torch ballast for 45 s.
# PASS: 0 spill lines during the hour; read speeds within 2 % of P167b g4a (529.21 s at 128k) / the usual 64k (P163 302.6 tok/s);
# the "other programs took" line after the ballast. Report min free VRAM and CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p168; mkdir -p $R
BIN=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
L='C:/bonsai/bonsai-ada-surgery/start-server-sg5test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
PROF=$(cygpath -w /c/bonsai/8gb/g5video/edgeprof)
"$EDGE" --user-data-dir="$PROF" --new-window --autoplay-policy=no-user-gesture-required --no-first-run "file:///C:/bonsai/8gb/g5video/g5.html" >/dev/null 2>&1 &
sleep 30
echo "$(date +%T) browser started; free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB; display $(nvidia-smi --query-gpu=display_active --format=csv,noheader)" > $R/run.txt
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free,utilization.gpu --format=csv,noheader,nounits)"; sleep 10; done ) > $R/mem.txt & MP=$!
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p168_g5 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p168_g5*.out.log | head -1); E="${O%.out.log}.err.log"
grep -hE "^(window|kv) " "$O" >> $R/run.txt
T0=$(date +%s)
rd() { PYTHONUTF8=1 python p168_read.py --key-file $KEY "$@" >> $R/run.txt 2>&1; }
rd --depth 128000 --salt s128
for k in 1 2 3; do
  while [ $(( $(date +%s) - T0 )) -lt $(( k * 900 )) ]; do sleep 20; done
  rd --depth 64000 --salt s64_$k; rd --short; rd --short; rd --short
  echo "$(date +%T) spill lines so far: $(grep -c '^spill' "$O")" >> $R/run.txt
done
while [ $(( $(date +%s) - T0 )) -lt 3600 ]; do sleep 20; done
echo "$(date +%T) hour done; spill lines during the hour: $(grep -c '^spill' "$O")" >> $R/run.txt
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=$((FREE - 100))
echo "$(date +%T) ballast $N MiB (free $FREE)" >> $R/run.txt
python gpu_ballast.py $N $R/ballast.pid >> $R/run.txt 2>&1 &
sleep 45
echo "$(date +%T) after 45 s: free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB; spill lines total: $(grep -c '^spill' "$O")" >> $R/run.txt
grep '^spill' "$O" >> $R/run.txt
BP=$(cat $R/ballast.pid 2>/dev/null); [ -n "$BP" ] && taskkill //PID $BP //F >/dev/null 2>&1
kill $MP
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
# close only the test browser (its own profile), never the user's
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe'\" | Where-Object { \$_.CommandLine -like '*g5video*edgeprof*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }"
{ cat $R/run.txt; awk '{v=$2+0; gsub(",","",$2); if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/mem.txt
  echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } > $R/summary.txt
