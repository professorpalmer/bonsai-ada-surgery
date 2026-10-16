#!/usr/bin/env bash
# P142 (post-zip check of bundle-20261015 on the 2060, as R08 / P138; the 4070 request on #21 11:42Z): zip 616,638,283 B,
# engine b86298dba9 (0056 q3_0 + 0057 packed-half dequant), launcher = release commit 0cbd0dcc (test copy + BONSAI_BIN).
# Default launcher, no BONSAI_CTK: must pick q3_0 and a line of ~80k.
# Gates (declared here, before the run): sha256 match; --version commit b86298dba9; ADD / RMS_NORM / FLASH_ATTN_EXT /
# GATED_DELTA_NET / SET_ROWS / CPY / GET_ROWS 0 FAIL; launcher prints q3_0 and line 78k-82k; sweep 4k / 64k / 128k within 3 % of
# P130 q3_0 (53.6 / 41.1 / 22.8); fresh 60k x2; 0 one-token; trace min free >= 60 MiB; BONSAI_SPARSE=1 at 245k prints the budget
# with 0.125 and runs (decode and min free reported).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p142; mkdir -p $R release_1015
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
[ -f release_1015/bonsai-bundle-win-x64.zip ] || gh release download bundle-20261015 -R professorpalmer/bonsai-ada-surgery -p bonsai-bundle-win-x64.zip -D release_1015 < /dev/null >> $R/zip.txt 2>&1
WANT=23db0bc477274314e817f3eaeda185b9ac314f31d346f45fc4861b2e3ae7dd16
GOT=$(powershell -NoProfile -Command "(Get-FileHash C:/bonsai/8gb/release_1015/bonsai-bundle-win-x64.zip -Algorithm SHA256).Hash.ToLower()" < /dev/null | tr -d '\r\n')
echo "size $(stat -c %s release_1015/bonsai-bundle-win-x64.zip) sha256 $GOT (want $WANT)" >> $R/zip.txt
[ "$GOT" = "$WANT" ] || { echo "SHA MISMATCH" >> $R/zip.txt; echo "sha mismatch: stop" > $R/summary.txt; exit 1; }
[ -d release_1015/x ] || powershell -NoProfile -Command "Expand-Archive -LiteralPath C:/bonsai/8gb/release_1015/bonsai-bundle-win-x64.zip -DestinationPath C:/bonsai/8gb/release_1015/x" < /dev/null >> $R/zip.txt 2>&1
EXE=$(find release_1015/x -name llama-server.exe | head -1)
[ -n "$EXE" ] || { echo "no llama-server.exe in zip" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$EXE")" && pwd -W); echo "BIN $BIN" >> $R/zip.txt
for o in ADD RMS_NORM FLASH_ATTN_EXT; do
  T="$BIN/test-backend-ops.exe"; [ -f "$T" ] || { echo "$o: no test-backend-ops in zip" >> $R/tests.txt; continue; }
  echo "$o: $("$T" -o $o -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')" >> $R/tests.txt
done
L='C:/bonsai/bonsai-ada-surgery/start-server-1015test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
memarm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.mem.txt & MP=$!; bash run_arm.sh $R "$@"; kill $MP; awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/$1.mem.txt >> $R/$1.txt; }
echo "version: $("$BIN/llama-server.exe" --version 2>&1 | tr -d '\r' | grep -iE 'version|commit' | head -2 | tr '\n' ' ')" >> $R/zip.txt
for o in GATED_DELTA_NET SET_ROWS CPY GET_ROWS; do echo "$o: $("$BIN/test-backend-ops.exe" -o $o -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r') FAIL $("$BIN/test-backend-ops.exe" -o $o -b CUDA0 < /dev/null 2>&1 | grep -c FAIL)" >> $R/tests.txt; done
memarm sweep "$V" "$L" "4000 64000 128000"
grep -hE "^(8gb|window|kv|spec|ckpt|note|warn|ram)" logs/*-sweep.out.log 2>/dev/null | tail -8 > $R/launcher_lines.txt
for r in 1 2; do memarm fresh60k_r$r "$V" "$L" "60000"; done
memarm sparse245 "$V;BONSAI_SPARSE=1" "$L" "245000"
O=$(ls -t logs/*-sparse245.out.log | head -1); grep -hE "^kv |budget|VRAM line" "$O" > $R/sparse245.launcher.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p142_ab -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag rel_d0 --out $R/ab.jsonl --depth 0 > $R/ab_d0.txt 2>&1
python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag rel_d64000 --out $R/ab.jsonl --depth 64000 > $R/ab_d64000.txt 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ cat $R/zip.txt $R/tests.txt $R/launcher_lines.txt; cat $R/sparse245.launcher.txt; for a in sweep fresh60k_r1 fresh60k_r2 sparse245; do f=$R/$a.txt; echo "== $a: $(grep -c '(1 tok)' $f) one-token"; grep -E "loaded|prose  depth|mean decode|did not|trace min" $f | sed -E 's/ttft +[0-9.]+s +//'; done; echo "gdn skip lines: $(grep -c \"skipped: device cc\" $(ls -t logs/*-sweep.err.log | head -1))"; echo "P130 q3_0 reference: 53.6 / 41.1 / 22.8 at 4k / 64k / 128k"; echo "ab one-token: $(grep -c '"n": 1,' $R/ab.jsonl) of $(wc -l < $R/ab.jsonl)"; } > $R/summary.txt
