#!/usr/bin/env bash
# P172 (release-20261017b R4 on the 2060: post-zip check; gates declared by the release session, #138 10:51Z): zip
# 616,671,821 B, SHA-256 6285cd5d...e79ce; bin/ = bundle-20261017; changed: README, start-server.ps1 (v6 spill guard), layer.
# The ZIP'S OWN start-server.ps1 runs unmodified, defaults (models = a junction to the rig's models folder; the rig api key
# copied into the zip's artifacts folder so the client can read it).
# Gates: 1) sha256 match; 2) zip launcher defaults: one cold 64k read within 2 % of P168 (309.3-309.6 tok/s) and 0 spill lines;
# 3) one ballast (free - 100 MiB) after the read: the spill line within 45 s; 4) 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p172; mkdir -p $R release_17b
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
[ -f release_17b/bonsai-bundle-win-x64.zip ] || gh release download bundle-20261017b -R professorpalmer/bonsai-ada-surgery -p bonsai-bundle-win-x64.zip -D release_17b < /dev/null >> $R/zip.txt 2>&1
WANT=6285cd5d6ef72e9e13ffadefb20b1ef91dd90afe80e53f3375bae268454e79ce
GOT=$(powershell -NoProfile -Command "(Get-FileHash C:/bonsai/8gb/release_17b/bonsai-bundle-win-x64.zip -Algorithm SHA256).Hash.ToLower()" < /dev/null | tr -d '\r\n')
echo "size $(stat -c %s release_17b/bonsai-bundle-win-x64.zip) sha256 $GOT (want $WANT)" >> $R/zip.txt
if [ "$GOT" = "$WANT" ]; then echo "G1 PASS" >> $R/run.txt; else echo "G1 FAIL (sha mismatch): stop" >> $R/run.txt; exit 1; fi
[ -d release_17b/x ] || powershell -NoProfile -Command "Expand-Archive -LiteralPath C:/bonsai/8gb/release_17b/bonsai-bundle-win-x64.zip -DestinationPath C:/bonsai/8gb/release_17b/x" < /dev/null >> $R/zip.txt 2>&1
ZL=$(find release_17b/x -name start-server.ps1 | head -1); ZR=$(dirname "$ZL")
echo "zip launcher: $ZL" >> $R/zip.txt
python -c "
import sys
b=open(sys.argv[1],'rb').read(); bad=[(i,c) for i,c in enumerate(b) if c<32 and c not in (9,10,13)]
print('zip launcher control bytes:', len(bad), bad[:5])
" "$(cygpath -w "$ZL")" >> $R/zip.txt
python -c "
import hashlib, os, sys
a, b = sys.argv[1], sys.argv[2]
diff = 0
for f in sorted(os.listdir(os.path.join(a, 'bin'))):
    h1 = hashlib.sha256(open(os.path.join(a, 'bin', f), 'rb').read()).hexdigest()
    p2 = os.path.join(b, 'bin', f)
    h2 = hashlib.sha256(open(p2, 'rb').read()).hexdigest() if os.path.exists(p2) else None
    diff += h1 != h2
    if h1 != h2: print('bin DIFFERENT:', f)
print('bin files compared to bundle-20261017:', len(os.listdir(os.path.join(a, 'bin'))), 'different:', diff)
" "$(cygpath -w "$ZR")" "$(cygpath -w release_1017/x)" >> $R/zip.txt
[ -e "$ZR/models" ] || powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$ZR")\models' -Target 'C:\bonsai\bonsai-ada-surgery\models'" < /dev/null >> $R/zip.txt 2>&1
mkdir -p "$ZR/artifacts"; cp -n C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt "$ZR/artifacts/api_key.txt"
KEY=$(cygpath -w "$ZR/artifacts/api_key.txt")
L=$(cygpath -w "$ZL")
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p172_r4 -Launcher "$L" -Vars "" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
O=$(ls -t logs/*p172_r4*.out.log | head -1); E="${O%.out.log}.err.log"
grep -hE "^(window|kv|vram|layer|spill|spec) " "$O" >> $R/run.txt
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 5; done ) > $R/mem.txt & MP=$!
sleep 20
PYTHONUTF8=1 python p168_read.py --key-file "$KEY" --depth 64000 --salt r4_64 >> $R/run.txt 2>&1
echo "$(date +%T) spill lines after the read: $(grep -c '^spill' "$O")" >> $R/run.txt
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | tr -d ' \r'); N=$((FREE - 100))
echo "$(date +%T) ballast $N MiB (free $FREE)" >> $R/run.txt
T0=$(date +%s)
python gpu_ballast.py $N $R/ballast.pid >> $R/run.txt 2>&1 &
BP=$!
for i in $(seq 1 45); do grep -q '^spill' "$O" && break; sleep 1; done
echo "$(date +%T) spill line after $(( $(date +%s) - T0 )) s: $(grep -c '^spill' "$O") line(s)" >> $R/run.txt
grep -h '^spill' "$O" | head -2 >> $R/run.txt
[ -f $R/ballast.pid ] && taskkill //F //PID "$(tr -d '\r\n ' < $R/ballast.pid)" >/dev/null 2>&1; kill $BP 2>/dev/null
sleep 3; kill $MP
echo "CUDA error lines: $(grep -ciE 'cuda error|out of memory' "$E")" >> $R/run.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
