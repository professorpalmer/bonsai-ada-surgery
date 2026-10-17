#!/usr/bin/env bash
# P163 (release-0062 S7 on the 2060: post-zip check of bundle-20261017, saved conversations on every card): zip 616,666,781 B,
# engine 96f6e49cdc, launcher / layer / docs 2db3fa21. The ZIP'S OWN start-server.ps1 runs (test copy, only the BONSAI_BIN line).
# Gates (declared before the run): sha256 match; zip launcher 0 control bytes; --version commit 96f6e49cdc; FLASH_ATTN_EXT /
# GET_ROWS / SET_ROWS 0 FAIL; default launch: "window 262144 / q3_0", "sparse host-tail reads: auto"; cold 128k TTFT within 3 %
# of P161 (536.8 s); a sweep 4k / 64k within 3 % of P161 (52.6 / 40.6); 0 one-token; trace min free >= 60 MiB; and the S1
# restore on the zip bins: BONSAI_SLOT_SAVE_PATH set, MTP on, shared pool on (defaults): prime 65,536 + save (a .draft file is
# written), two fresh restores + ~4k new tokens each >= 150 tok/s new-token prompt eval, answers equal, 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p163; mkdir -p $R release_1017
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
[ -f release_1017/bonsai-bundle-win-x64.zip ] || gh release download bundle-20261017 -R professorpalmer/bonsai-ada-surgery -p bonsai-bundle-win-x64.zip -D release_1017 < /dev/null >> $R/zip.txt 2>&1
WANT=723c12e68a029a5e34f6a66307d8292c311f9a8a79ed6689973d1fd46718c253
GOT=$(powershell -NoProfile -Command "(Get-FileHash C:/bonsai/8gb/release_1017/bonsai-bundle-win-x64.zip -Algorithm SHA256).Hash.ToLower()" < /dev/null | tr -d '\r\n')
echo "size $(stat -c %s release_1017/bonsai-bundle-win-x64.zip) sha256 $GOT (want $WANT)" >> $R/zip.txt
[ "$GOT" = "$WANT" ] || { echo "SHA MISMATCH" >> $R/zip.txt; echo "sha mismatch: stop" > $R/summary.txt; exit 1; }
[ -d release_1017/x ] || powershell -NoProfile -Command "Expand-Archive -LiteralPath C:/bonsai/8gb/release_1017/bonsai-bundle-win-x64.zip -DestinationPath C:/bonsai/8gb/release_1017/x" < /dev/null >> $R/zip.txt 2>&1
EXE=$(find release_1017/x -name llama-server.exe | head -1); BIN=$(cd "$(dirname "$EXE")" && pwd -W); echo "BIN $BIN" >> $R/zip.txt
ZL=$(find release_1017/x -name start-server.ps1 | head -1); echo "zip launcher: $ZL" >> $R/zip.txt
python -c "
import sys
b=open(sys.argv[1],'rb').read(); bad=[(i,c) for i,c in enumerate(b) if c<32 and c not in (9,10,13)]
print('zip launcher control bytes:', len(bad), bad[:5])
" "$(cygpath -w "$ZL")" >> $R/zip.txt
python -c "
import sys
s=open(sys.argv[1],'rb').read(); o=b\"\$Bin = Join-Path \$Root 'bin'\"
assert s.count(o)==1
s=s.replace(o, b\"\$Bin = if (\$env:BONSAI_BIN) { \$env:BONSAI_BIN } else { Join-Path \$Root 'bin' }   # P163 test copy of the bundle-20261017 zip launcher\")
open(r'C:\bonsai\bonsai-ada-surgery\start-server-1017test.ps1','wb').write(s)
" "$(cygpath -w "$ZL")" && echo "test copy written" >> $R/zip.txt
echo "version: $("$BIN/llama-server.exe" --version 2>&1 | tr -d '\r' | grep -iE 'commit' | head -1)" >> $R/zip.txt
for op in FLASH_ATTN_EXT GET_ROWS SET_ROWS; do echo "$op: $("$BIN/test-backend-ops.exe" -o $op -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')"; done > $R/tests.txt
CALU=$(cygpath -u "$LOCALAPPDATA/bonsai/sparse-calib.txt"); [ -f "$CALU" ] && mv "$CALU" "$CALU.before-p150"
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
memarm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.mem.txt & MP=$!; bash run_arm.sh $R "$@"; kill $MP
  awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/$1.mem.txt >> $R/$1.txt
  O=$(ls -t logs/*-$1.out.log | head -1); grep -hE "^(window|kv) " "$O" > $R/$1.launcher.txt; }
memarm cold128 "$V" "$L" "128000"
memarm sweep "$V" "$L" "4000 64000"; cp "$CALU" $R/calib_after.txt 2>/dev/null

# S1 on the zip bins: save / restore with MTP on and the shared pool on
mkdir -p slots163; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt; SW='C:\bonsai\8gb\slots163'; VS="$V;BONSAI_SLOT_SAVE_PATH=$SW"
sserve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p163_$1 -Launcher "$L" -Vars "$VS" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
rrun() { PYTHONUTF8=1 python p157_restore.py --key-file $KEY --depth 65536 --file z.bin --state $R/stateZ.json --out $R/restore.jsonl "$@" >> $R/restore.txt 2>&1; }
sserve zprime; rrun --phase prime --tag zprime; ls -l slots163 >> $R/restore.txt
for t in z1 z2; do sserve $t; rrun --phase cont --new 4000 --tag $t; E=$(ls -t logs/*p163_$t*.err.log | head -1); grep -hE "prompt eval time|draft context|CUDA error|grew|failed in" "$E" | tail -5 >> $R/restore.txt; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; rm -rf slots163
echo "CUDA error logs (p163): $(grep -l 'CUDA error' logs/*p163_*.err.log 2>/dev/null | wc -l)" >> $R/restore.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ cat $R/zip.txt $R/tests.txt; for a in cold128 sweep; do echo "== $a: $(grep -c '(1 tok)' $R/$a.txt) one-token"; cat $R/$a.launcher.txt; grep -E "loaded|mean decode|did not|trace min" $R/$a.txt; done
  echo "reference: P161 cold 128k 536.8 s; 4k 52.6, 64k 40.6"; grep -h "^code" $R/cold128.txt $R/sweep.txt; echo "== calib after"; cat $R/calib_after.txt 2>/dev/null; echo "== S1 restore"; cut -c1-300 $R/restore.jsonl; cat $R/restore.txt; } > $R/summary.txt
