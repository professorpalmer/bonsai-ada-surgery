#!/usr/bin/env bash
# P171 (cold-read selector with a small model, after P170; #138): phase 1 = Qwen2.5-1.5B-Instruct q4_k_m (already in the local
# HF cache, no download) on a plain llama-server (bundle-20261017 zip bins, -ngl 99, 16 slots x 2,048, :8090, Bonsai stopped)
# rates every 400-char chunk of the P170 sets against each question (P(Yes) for "does the passage contain the answer");
# phase 2 = the product Bonsai server (as P170) reads the kept text: arm small (best-rated chunks to 16,384 tokens) and arm mix
# (alternate small / text-match picks). Reported per set: scoring time per question, the fact's rank, fact kept, answers, time.
# No pass / fail (a selector study); the reference is P170 dense on the same sets.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p171; mkdir -p $R
ZIPU="$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")"
ZIP=$(cygpath -w "$(cd "$ZIPU" && pwd)")
QM=$(cygpath -w /c/Users/<user>/.cache/huggingface/hub/models--Qwen--Qwen2.5-1.5B-Instruct-GGUF/snapshots/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$ZIP;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; sleep 3
"$ZIPU/llama-server.exe" -m "$QM" -ngl 99 -c 32768 -np 16 -fa on --host 127.0.0.1 --port 8090 > $R/scorer.log 2>&1 &
SP=$!
for i in $(seq 1 90); do curl -s 127.0.0.1:8090/health | grep -q ok && break; sleep 2; done
echo "$(date +%T) scorer up (free $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) MiB)" >> $R/run.txt
for s in code prose; do
  PYTHONUTF8=1 python p171_score.py --set $s --threads 16 > $R/score_$s.txt 2>&1
  echo "$(date +%T) scored $s: $(grep -c '"item"' $R/score_$s.txt) items" >> $R/run.txt
done
kill $SP 2>/dev/null; sleep 2; taskkill //F //IM llama-server.exe >/dev/null 2>&1; sleep 3
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p171_$1" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p171_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$(date +%T) $1 up: $(grep -hE '^kv +tiered' "$O" | cut -c1-80)" >> $R/run.txt
}
for s in code prose; do
  [ -f p170/scores_$s.json ] || { echo "$(date +%T) no scores for $s" >> $R/run.txt; continue; }
  for arm in small mix; do
    serve ${s}_$arm
    PYTHONUTF8=1 python p170_drive.py --set $s --arm $arm --keep 16384 --key-file $KEY --out $R/$s.jsonl > $R/${s}_$arm.txt 2>&1
    echo "$(date +%T) $s $arm ok $(grep -c '"ok": true' $R/${s}_$arm.txt) of $(grep -c '"item"' $R/${s}_$arm.txt); fact kept $(grep -c '"fact_kept": true' $R/${s}_$arm.txt); CUDA error lines $(grep -ciE 'cuda error|out of memory' "$E")" >> $R/run.txt
  done
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
