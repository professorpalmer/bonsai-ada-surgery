#!/usr/bin/env bash
# P186 (PR #171 G2 on the 2060: the 8 GB pool reserve; gates declared in PR2, #138 comment 6235261102 / 6236213480): the zip bins
# of bundle-20261017b (release_17b/x/bin) + the PR head launcher 5125d445 (copied as release_17b/x/start-server-171.ps1, so its
# Root finds the zip's bin, the models junction and artifacts), defaults, the display on the 2060.
# Gates: 1) the launcher prints "pool reserved 176 MiB" in its 8gb line; 2) cold 128k within 2 % of P168 (239.2 tok/s) and trace
# min free >= 70 MiB (P168 86 - 16), 0 spill lines; 3) a small ballast (free - 100) after the reads, then a cold 16k read: close
# to the no-ballast 16k read just before it (P167b squeeze without the reserve: 70.1 tok/s); 4) 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p186; mkdir -p $R
L=$(cygpath -w release_17b/x/start-server-171.ps1); KEY=$(cygpath -w release_17b/x/artifacts/api_key.txt)
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 5; done ) > $R/mem.txt & MP=$!
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p186_g2 -Launcher "$L" -Vars "" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p186_g2*.out.log | head -1); E="${O%.out.log}.err.log"
grep -hE "^(8gb|window|kv|vram|spec|layer|spill) " "$O" >> $R/run.txt
echo "G1: $(grep -c 'pool reserved 176 MiB' "$O") line(s) with 'pool reserved 176 MiB'" >> $R/run.txt
sleep 20
PYTHONUTF8=1 python p168_read.py --key-file "$KEY" --depth 128000 --salt g2_128 >> $R/run.txt 2>&1
echo "$(date +%T) spill lines after 128k: $(grep -c '^spill' "$O")" >> $R/run.txt
PYTHONUTF8=1 python p168_read.py --key-file "$KEY" --depth 16000 --salt g2_16a >> $R/run.txt 2>&1
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=$((FREE - 100))
echo "$(date +%T) ballast $N MiB (free $FREE)" >> $R/run.txt
python gpu_ballast.py $N $R/ballast.pid >> $R/run.txt 2>&1 &
sleep 20
PYTHONUTF8=1 python p168_read.py --key-file "$KEY" --depth 16000 --salt g2_16b >> $R/run.txt 2>&1
echo "$(date +%T) spill lines total: $(grep -c '^spill' "$O")" >> $R/run.txt
BP=$(cat $R/ballast.pid 2>/dev/null); [ -n "$BP" ] && taskkill //PID $(echo $BP | tr -d '\r\n ') //F >/dev/null 2>&1
sleep 3; kill $MP
awk '{v=$2+0; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/mem.txt >> $R/run.txt
echo "CUDA error lines: $(grep -ciE 'cuda error|out of memory' "$E")" >> $R/run.txt
grep -hiE "pool.*(grow|reserve)" "$E" | head -5 >> $R/run.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
