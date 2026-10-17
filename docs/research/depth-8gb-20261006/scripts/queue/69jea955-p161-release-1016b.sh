#!/usr/bin/env bash
# P161 (post-zip check of bundle-20261016b on the 2060: patches 0060 / 0061, the Turing prefill tiles on by default on sm_75):
# zip 616,655,338 B, engine 9fae15924e, launcher baa7275b. The ZIP'S OWN start-server.ps1 runs (test copy, only the BONSAI_BIN
# line added).
# Gates (declared before the run): sha256 match; zip launcher 0 control bytes; --version commit 9fae15924e; FLASH_ATTN_EXT /
# GET_ROWS / SET_ROWS 0 FAIL; the default launch prints "window 262144 / q3_0" and "sparse host-tail reads: auto"; a COLD
# 128k read (fresh server) TTFT <= 0.95 x P154's default (589.1 s) [P154 NCOLS2=2: 530.8 s]; a sweep 4k / 64k on a second
# server within 3 % of P150 (54.0 / 41.1); 0 one-token; trace min free >= 60 MiB.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p161; mkdir -p $R release_1016b
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
[ -f release_1016b/bonsai-bundle-win-x64.zip ] || gh release download bundle-20261016b -R professorpalmer/bonsai-ada-surgery -p bonsai-bundle-win-x64.zip -D release_1016b < /dev/null >> $R/zip.txt 2>&1
WANT=fe5a3845fe7bef2d813bd385e47c5e818628eacf0427332ab7b8275f9c843f6b
GOT=$(powershell -NoProfile -Command "(Get-FileHash C:/bonsai/8gb/release_1016b/bonsai-bundle-win-x64.zip -Algorithm SHA256).Hash.ToLower()" < /dev/null | tr -d '\r\n')
echo "size $(stat -c %s release_1016b/bonsai-bundle-win-x64.zip) sha256 $GOT (want $WANT)" >> $R/zip.txt
[ "$GOT" = "$WANT" ] || { echo "SHA MISMATCH" >> $R/zip.txt; echo "sha mismatch: stop" > $R/summary.txt; exit 1; }
[ -d release_1016b/x ] || powershell -NoProfile -Command "Expand-Archive -LiteralPath C:/bonsai/8gb/release_1016b/bonsai-bundle-win-x64.zip -DestinationPath C:/bonsai/8gb/release_1016b/x" < /dev/null >> $R/zip.txt 2>&1
EXE=$(find release_1016b/x -name llama-server.exe | head -1); BIN=$(cd "$(dirname "$EXE")" && pwd -W); echo "BIN $BIN" >> $R/zip.txt
ZL=$(find release_1016b/x -name start-server.ps1 | head -1); echo "zip launcher: $ZL" >> $R/zip.txt
python -c "
import sys
b=open(sys.argv[1],'rb').read(); bad=[(i,c) for i,c in enumerate(b) if c<32 and c not in (9,10,13)]
print('zip launcher control bytes:', len(bad), bad[:5])
" "$(cygpath -w "$ZL")" >> $R/zip.txt
python -c "
import sys
s=open(sys.argv[1],'rb').read(); o=b\"\$Bin = Join-Path \$Root 'bin'\"
assert s.count(o)==1
s=s.replace(o, b\"\$Bin = if (\$env:BONSAI_BIN) { \$env:BONSAI_BIN } else { Join-Path \$Root 'bin' }   # P161 test copy of the bundle-20261016b zip launcher\")
open(r'C:\bonsai\bonsai-ada-surgery\start-server-1016btest.ps1','wb').write(s)
" "$(cygpath -w "$ZL")" && echo "test copy written" >> $R/zip.txt
echo "version: $("$BIN/llama-server.exe" --version 2>&1 | tr -d '\r' | grep -iE 'commit' | head -1)" >> $R/zip.txt
for op in FLASH_ATTN_EXT GET_ROWS SET_ROWS; do echo "$op: $("$BIN/test-backend-ops.exe" -o $op -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')"; done > $R/tests.txt
CALU=$(cygpath -u "$LOCALAPPDATA/bonsai/sparse-calib.txt"); [ -f "$CALU" ] && mv "$CALU" "$CALU.before-p150"
L='C:/bonsai/bonsai-ada-surgery/start-server-1016btest.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
memarm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.mem.txt & MP=$!; bash run_arm.sh $R "$@"; kill $MP
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/$1.mem.txt >> $R/$1.txt
  O=$(ls -t logs/*-$1.out.log | head -1); grep -hE "^(window|kv) " "$O" > $R/$1.launcher.txt; }
memarm cold128 "$V" "$L" "128000"
memarm sweep "$V" "$L" "4000 64000"; cp "$CALU" $R/calib_after.txt 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ cat $R/zip.txt $R/tests.txt; for a in cold128 sweep; do echo "== $a: $(grep -c '(1 tok)' $R/$a.txt) one-token"; cat $R/$a.launcher.txt; grep -E "loaded|mean decode|did not|trace min" $R/$a.txt; done
  echo "reference: P154 cold 128k default 589.1 s / NCOLS2=2 530.8 s; P150 4k 54.0, 64k 41.1"; grep -h "^code" $R/cold128.txt $R/sweep.txt; echo "== calib after"; cat $R/calib_after.txt 2>/dev/null; } > $R/summary.txt
