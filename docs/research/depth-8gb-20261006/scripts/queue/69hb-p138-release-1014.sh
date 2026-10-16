#!/usr/bin/env bash
# P138 (R06 on the published zip): bundle-20261014 (patch 0055, sparse opt-in BONSAI_SPARSE=1), zip 611,390,390 B, release
# commit bfae9143, engine LLAMA_COMMIT 4de6185494 (sm 75/86/89). Launcher: test copy of bfae9143 start-server.ps1 + BONSAI_BIN
# (= the tested #49 3035572 + #75). Default switches (sparse off).
# Gates (declared here, before the run): sha256 match; ADD / RMS_NORM / FLASH_ATTN_EXT / GATED_DELTA_NET pass; the zip bins
# report commit 4de6185494; default-off decode at 64k / 96k / 128k within 3 % of bundle-20261013 in the same session (A/B
# alternated x2 below); sweep 4k-128k reported; fresh 60k x2; 0 one-token; trace min free >= 60 MiB. Note: the zip is a fat
# sm 75/86/89 build, so its ggml-cuda.dll is not byte-equal to the rig's 75-real bin-rc55 (hashes reported, not gated);
# P139 reruns the sparse checks on the zip bins.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p138; mkdir -p $R release_1014
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
[ -f release_1014/bonsai-bundle-win-x64.zip ] || gh release download bundle-20261014 -R professorpalmer/bonsai-ada-surgery -p bonsai-bundle-win-x64.zip -D release_1014 < /dev/null >> $R/zip.txt 2>&1
WANT=c91dfc98f82c74db93370568e47210d2e6c98c2907ed7aef872ba3bf5ab24cd0
GOT=$(powershell -NoProfile -Command "(Get-FileHash C:/bonsai/8gb/release_1014/bonsai-bundle-win-x64.zip -Algorithm SHA256).Hash.ToLower()" < /dev/null | tr -d '\r\n')
echo "size $(stat -c %s release_1014/bonsai-bundle-win-x64.zip) sha256 $GOT (want $WANT)" >> $R/zip.txt
[ "$GOT" = "$WANT" ] || { echo "SHA MISMATCH" >> $R/zip.txt; echo "sha mismatch: stop" > $R/summary.txt; exit 1; }
[ -d release_1014/x ] || powershell -NoProfile -Command "Expand-Archive -LiteralPath C:/bonsai/8gb/release_1014/bonsai-bundle-win-x64.zip -DestinationPath C:/bonsai/8gb/release_1014/x" < /dev/null >> $R/zip.txt 2>&1
EXE=$(find release_1014/x -name llama-server.exe | head -1)
[ -n "$EXE" ] || { echo "no llama-server.exe in zip" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$EXE")" && pwd -W); echo "BIN $BIN" >> $R/zip.txt
for o in ADD RMS_NORM FLASH_ATTN_EXT; do
  T="$BIN/test-backend-ops.exe"; [ -f "$T" ] || { echo "$o: no test-backend-ops in zip" >> $R/tests.txt; continue; }
  echo "$o: $("$T" -o $o -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')" >> $R/tests.txt
done
L='C:/bonsai/bonsai-ada-surgery/start-server-1014test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
memarm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.mem.txt & MP=$!; bash run_arm.sh $R "$@"; kill $MP; awk '{v=$2+0; if (v>4000000) v=v-4194304; if (NR==1||v<m) m=v} END{print "trace min free", m, "MiB over", NR, "samples"}' $R/$1.mem.txt >> $R/$1.txt; }
echo "version: $("$BIN/llama-server.exe" --version 2>&1 | tr -d '\r' | grep -iE 'version|commit' | head -2 | tr '\n' ' ')" >> $R/zip.txt
for f in ggml-cuda.dll llama-server.exe llama.dll ggml.dll; do echo "$f zip $(sha256sum "$BIN/$f" 2>/dev/null | cut -c1-16) rc55 $(sha256sum /c/bonsai/bonsai-ada-surgery/bin-rc55/$f 2>/dev/null | cut -c1-16)" >> $R/hashes.txt; done
echo "GATED_DELTA_NET: $("$BIN/test-backend-ops.exe" -o GATED_DELTA_NET -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed' | tr -d '\r')" >> $R/tests.txt
B13=$(cd /c/bonsai/8gb/release_1013/x/bin && pwd -W)
for r in 1 2; do
  bash run_arm.sh $R ab1013_r$r "BONSAI_BIN=$B13;BONSAI_LAYER=0" "$L" "64000 96000 128000"
  bash run_arm.sh $R ab1014_r$r "$V" "$L" "64000 96000 128000"
done
memarm sweep "$V" "$L" "4000 32000 64000 96000 128000"
grep -hE "^(8gb|window|kv|spec|ckpt|note|warn|ram)" logs/*-sweep.out.log 2>/dev/null | tail -8 > $R/launcher_lines.txt
for r in 1 2; do memarm fresh60k_r$r "$V" "$L" "60000"; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p138_ab -Launcher "$L" -Vars "$V" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag rel_d0 --out $R/ab.jsonl --depth 0 > $R/ab_d0.txt 2>&1
python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag rel_d64000 --out $R/ab.jsonl --depth 64000 > $R/ab_d64000.txt 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ cat $R/zip.txt $R/hashes.txt $R/tests.txt $R/launcher_lines.txt; for a in ab1013_r1 ab1014_r1 ab1013_r2 ab1014_r2; do echo "== $a: $(grep -c '(1 tok)' $R/$a.txt) one-token"; grep -E "mean decode|did not" $R/$a.txt; done; for a in sweep fresh60k_r1 fresh60k_r2; do f=$R/$a.txt; echo "== $a: $(grep -c '(1 tok)' $f) one-token"; grep -E "loaded|prose  depth|mean decode|did not|trace min" $f | sed -E 's/ttft +[0-9.]+s +//'; done; echo "gdn skip lines: $(grep -c \"skipped: device cc\" $(ls -t logs/*-sweep.err.log | head -1))"; echo "ab one-token: $(grep -c '"n": 1,' $R/ab.jsonl) of $(wc -l < $R/ab.jsonl)"; } > $R/summary.txt
