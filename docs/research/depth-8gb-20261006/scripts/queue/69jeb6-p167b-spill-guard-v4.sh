#!/usr/bin/env bash
# P167b (spill guard v4 02523b9, #138 08:01Z) - the VALID G4 run. P166 / P167 G4b were invalid: the guard finds the server with
# $srv.Path.StartsWith($BinDir), and the test passed BONSAI_BIN with forward slashes (C:/bonsai/...), while the process path has
# backslashes, so the guard never found the server and never ran. Here BONSAI_BIN is the Windows form (cygpath -w at run time).
# Launcher: 02523b9 test copy (BONSAI_BIN line only) on the bundle-20261017 zip bins, defaults. Arms (gates as declared on #138):
#   small: a (free - 100) MiB torch ballast after /health, 45 s -> the "other programs took" line; then a cold 16k read.
#   big:   a 1,500 MiB ballast, 45 s, the ballast's GPU counters (Get-Counter: Dedicated / Shared / Total Committed) -> the line
#          BEFORE the read; then a cold 16k read (it crashed with CUDA OOM in P166b / P167).
#   g4a:   defaults, cold 128k, no ballast -> 0 lines, TTFT within 2 % of P166 (530.8 s).
# Report the first-sample free VRAM, the read speeds, the spill lines with their times, CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p167b; mkdir -p $R
BIN=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
L='C:/bonsai/bonsai-ada-surgery/start-server-sg4test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
echo "BONSAI_BIN as passed: $BIN" > $R/summary.txt
hog() {   # $1 tag, $2 ballast MiB or "free" (free - 100)
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p167b_$1 -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  sleep 20   # the guard takes its base at the first good /health, then samples every 15 s
  O=$(ls -t logs/*p167b_$1*.out.log | head -1); E="${O%.out.log}.err.log"; T=$R/$1.txt
  FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r')
  N=$2; [ "$N" = free ] && N=$((FREE - 100))
  echo "$(date +%T) free $FREE MiB, ballast $N MiB" > $T
  python gpu_ballast.py $N $R/ballast_$1.pid >> $T 2>&1 &
  sleep 45
  echo "$(date +%T) after 45 s: free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB" >> $T
  BP=$(cat $R/ballast_$1.pid 2>/dev/null); [ -n "$BP" ] && powershell -NoProfile -ExecutionPolicy Bypass -File C:/bonsai/8gb/gpu_counters.ps1 -ProcId $BP >> $T 2>&1
  echo "spill lines before the read: $(grep -c '^spill' "$O")" >> $T; grep '^spill' "$O" >> $T
  PYTHONUTF8=1 python /c/bonsai/bonsai-ada-surgery/bench/quick_tps.py --base http://127.0.0.1:8080 --key-file $KEY --depth 16000 2>&1 | grep -E "depth|mean decode|rror" >> $T
  [ -n "$BP" ] && taskkill //PID $BP //F >/dev/null 2>&1
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  { echo "== $1"; cat $T; echo "spill lines (all): $(grep -c '^spill' "$O")"; echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } >> $R/summary.txt; }
hog small free
hog big 1500
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/g4a.mem.txt & MP=$!
bash run_arm.sh $R g4a "$V" "$L" "128000"; kill $MP
O=$(ls -t logs/*-g4a.out.log | head -1); E="${O%.out.log}.err.log"
{ echo "== g4a"; grep -E "^code|mean decode|did not" $R/g4a.txt; echo "spill lines: $(grep -c '^spill' "$O")"; grep '^spill' "$O";
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/g4a.mem.txt
  echo "CUDA errors: $(grep -c 'CUDA error' "$E")"; } >> $R/summary.txt
