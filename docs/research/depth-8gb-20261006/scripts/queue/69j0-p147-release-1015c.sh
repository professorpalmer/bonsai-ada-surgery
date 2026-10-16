#!/usr/bin/env bash
# P147 (post-zip check of bundle-20261015c on the 2060, asked on #105 16:56Z: new llama-server with patch 0058, 3 rebuilt ggml DLLs): zip 616,639,105 B,
# same launcher as 15b. Runs while the D26h engine builds (CPU -j 4): a decode miss is re-run after the build before any verdict. The test uses the ZIP'S OWN start-server.ps1 (copied next to the repo's models with only the
# BONSAI_BIN line added), so the shipped launcher logic is what runs.
# Gates (declared here, before the run): sha256 match; the zip's start-server.ps1 has no control bytes (0x00-0x08, 0x0B, 0x0C,
# 0x0E-0x1F); --version commit c2cf6d6450; ADD, GET_ROWS, FLASH_ATTN_EXT 0 FAIL; default launch (no BONSAI_CTK) prints "window 262144 / q3_0" and a
# line of 78k-82k; 4k / 64k within 3 % of P130 q3_0 (53.6 / 41.0); 0 one-token; trace min free >= 60.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p147; mkdir -p $R release_1015c
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
[ -f release_1015c/bonsai-bundle-win-x64.zip ] || gh release download bundle-20261015c -R professorpalmer/bonsai-ada-surgery -p bonsai-bundle-win-x64.zip -D release_1015c < /dev/null >> $R/zip.txt 2>&1
WANT=a46ae100baef2ba38ad48a0a40c28c0e975d394e958e29dbe7b140a272f2560a
GOT=$(powershell -NoProfile -Command "(Get-FileHash C:/bonsai/8gb/release_1015c/bonsai-bundle-win-x64.zip -Algorithm SHA256).Hash.ToLower()" < /dev/null | tr -d '\r\n')
echo "size $(stat -c %s release_1015c/bonsai-bundle-win-x64.zip) sha256 $GOT (want $WANT)" >> $R/zip.txt
[ "$GOT" = "$WANT" ] || { echo "SHA MISMATCH" >> $R/zip.txt; echo "sha mismatch: stop" > $R/summary.txt; exit 1; }
[ -d release_1015c/x ] || powershell -NoProfile -Command "Expand-Archive -LiteralPath C:/bonsai/8gb/release_1015c/bonsai-bundle-win-x64.zip -DestinationPath C:/bonsai/8gb/release_1015c/x" < /dev/null >> $R/zip.txt 2>&1
EXE=$(find release_1015c/x -name llama-server.exe | head -1); BIN=$(cd "$(dirname "$EXE")" && pwd -W); echo "BIN $BIN" >> $R/zip.txt
ZL=$(find release_1015c/x -name start-server.ps1 | head -1); echo "zip launcher: $ZL" >> $R/zip.txt
python -c "
import sys
b=open(sys.argv[1],'rb').read(); bad=[(i,c) for i,c in enumerate(b) if c<32 and c not in (9,10,13)]
print('zip launcher control bytes:', len(bad), bad[:5])
" "$(cygpath -w "$ZL")" >> $R/zip.txt
python -c "
import sys
s=open(sys.argv[1],'rb').read(); o=b\"\$Bin = Join-Path \$Root 'bin'\"
assert s.count(o)==1
s=s.replace(o, b\"\$Bin = if (\$env:BONSAI_BIN) { \$env:BONSAI_BIN } else { Join-Path \$Root 'bin' }   # P147 test copy of the bundle-20261015c zip launcher\")
open(r'C:\bonsai\bonsai-ada-surgery\start-server-1015ctest.ps1','wb').write(s)
" "$(cygpath -w "$ZL")" && echo "test copy written" >> $R/zip.txt
echo "version: $("$BIN/llama-server.exe" --version 2>&1 | tr -d '\r' | grep -iE 'commit' | head -1)" >> $R/zip.txt
for op in ADD GET_ROWS FLASH_ATTN_EXT; do echo "$op: $("$BIN/test-backend-ops.exe" -o $op -b CUDA0 < /dev/null 2>&1 | grep -E "tests passed" | tr -d '\r')"; done > $R/tests.txt; grep -c "q3_0" < <("$BIN/test-backend-ops.exe" -o FLASH_ATTN_EXT -b CUDA0 < /dev/null 2>&1) | sed "s/^/FA q3_0 cases: /" >> $R/tests.txt
L='C:/bonsai/bonsai-ada-surgery/start-server-1015ctest.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
memarm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.mem.txt & MP=$!; bash run_arm.sh $R "$@"; kill $MP
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/$1.mem.txt >> $R/$1.txt
  O=$(ls -t logs/*-$1.out.log | head -1); grep -hE "^(window|kv) " "$O" > $R/$1.launcher.txt; }
memarm sweep "$V" "$L" "4000 64000"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ cat $R/zip.txt $R/tests.txt; for a in sweep; do echo "== $a: $(grep -c '(1 tok)' $R/$a.txt) one-token"; cat $R/$a.launcher.txt; grep -E "loaded|mean decode|did not|trace min" $R/$a.txt; done
  echo "P130 q3_0 reference: 53.6 / 41.0 at 4k / 64k"; } > $R/summary.txt
