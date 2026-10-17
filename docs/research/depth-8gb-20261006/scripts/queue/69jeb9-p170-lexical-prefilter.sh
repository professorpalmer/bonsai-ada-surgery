#!/usr/bin/env bash
# P170 (cold-read selectors without a model pass over the full input; #138 post 6232969793): the product bins (bundle-20261017
# zip) + the 1017 launcher copy, layer off, line pinned 80,640 (as P169), fresh server per arm. Sets (p170_build.py, fixed in
# p170/): prose = ~241.8k tokens of the repo research notes with 24 inserted facts, questions in other words; code = ~240.4k
# tokens of llama.cpp CUDA + src code with 24 inserted constants, 12 questions name the identifier, 12 describe it.
# Arms per set: lex (p170_drive.py: BM25 chunks, sinks 256 + window 2048 + best chunks to 16,384 tokens) then dense (full doc,
# the server reuses the cached prefix after the first item). Dry run before queueing: lex keeps the fact for prose 6/24,
# code 13/24 (all 12 named + 1 described).
# Reported (no pass / fail; a selector study): per item ok, fact kept, time; dense = the reference for every later selector.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p170; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$ZIP;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p170_$1" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p170_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$(date +%T) $1 up: $(grep -hE '^kv +tiered' "$O" | cut -c1-80)" >> $R/run.txt
}
for s in code prose; do
  for arm in lex dense; do
    serve ${s}_$arm
    PYTHONUTF8=1 python p170_drive.py --set $s --arm $arm --keep 16384 --key-file $KEY --out $R/$s.jsonl > $R/${s}_$arm.txt 2>&1
    echo "$(date +%T) $s $arm ok $(grep -c '"ok": true' $R/${s}_$arm.txt) of $(grep -c '"item"' $R/${s}_$arm.txt); CUDA error lines $(grep -ciE 'cuda error|out of memory' "$E")" >> $R/run.txt
  done
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
