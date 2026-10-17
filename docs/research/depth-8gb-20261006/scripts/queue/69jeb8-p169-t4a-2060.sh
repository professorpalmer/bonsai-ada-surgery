#!/usr/bin/env bash
# P169 (T4-A fast read on the 2060, sm_75; gates of #138 08:37Z, applied to the 2060): bin-t4b = t4-fastread-b f7d988d88 (the
# kernel session's T4 diff + bmax), built here for 75-real on the bundle-20261017 engine tree (96f6e49cd = 4fcd19004, no diff).
# Launcher: start-server-1017test.ps1 (bundle-20261017 launcher), BONSAI_BIN override, layer off, line pinned 80,640.
# T4-0 (must pass): det_answer at 4k and 32k, fresh server each, product zip bins vs bin-t4b with LLAMA_FAST_READ unset:
#   equal sha256 at both depths.
# T4-1: the first n24 request's wall time at 245k (cold, includes the scoring pass), vs the 2060 dense cold ~1,489 s (P151/16b).
# T4-2: needle n24 at 245k with LLAMA_FAST_READ=keep=16384,bmax=1; dense ref on the 2060 = P148: 23/24 (miss vault 14).
# No pass / fail for T4 itself (opt-in lossy mode); report speed and every lost item. 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p169; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
T4=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t4b)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
BASEV="BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p169_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p169_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$(date +%T) $1 up: $(grep -hE '^kv +tiered' "$O" | cut -c1-80)" >> $R/run.txt
}
cuda() { echo "$(date +%T) $1 CUDA error lines: $(grep -ciE 'cuda error|out of memory' "$E")" >> $R/run.txt; }
for arm in zip t4off; do
  B=$ZIP; [ $arm = t4off ] && B=$T4
  for d in 4000 32000; do
    serve ${arm}_d$d "BONSAI_BIN=$B;$BASEV"
    PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth $d --out $R/${arm}_d$d.txt >> $R/run.txt 2>&1
    echo "$(date +%T) $arm d$d sha256 $(sha256sum $R/${arm}_d$d.txt | cut -c1-16)" >> $R/run.txt; cuda ${arm}_d$d
  done
done
for d in 4000 32000; do
  a=$(sha256sum < $R/zip_d$d.txt); b=$(sha256sum < $R/t4off_d$d.txt)
  [ "$a" = "$b" ] && echo "T4-0 d$d PASS" >> $R/run.txt || echo "T4-0 d$d FAIL" >> $R/run.txt
done
if grep -q "T4-0 .* FAIL" $R/run.txt; then echo "$(date +%T) T4-0 failed: stop" >> $R/run.txt; exit 0; fi
serve k16b "BONSAI_BIN=$T4;$BASEV;LLAMA_FAST_READ=keep=16384,bmax=1"
grep -hiE "fast.?read" "$O" "$E" | head -5 >> $R/run.txt
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag t4_k16b_245000 --out $R/needle24.jsonl > $R/k16b_n24.txt 2>&1
tail -1 $R/k16b_n24.txt >> $R/run.txt; cuda k16b
grep -hiE "fast.?read|T4" "$E" | tail -30 > $R/k16b_t4_log.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
