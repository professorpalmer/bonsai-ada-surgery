#!/usr/bin/env bash
# P179 (does the capture guard fix the P177 crash?): bin-t5r2 (runs + cudaStreamIsCapturing guard), GGML_CUDA_FA_CHUNK=8192,
# window 16k / sink 1k / tail 1k: det_answer at 32k (P177 C crashed here) and at 64k (the skip active). Gate: 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p179; mkdir -p $R
T=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r2)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$T;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0;GGML_CUDA_FA_CHUNK=8192;LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024"
for d in 32000 64000; do
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p179_d$d" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p179_d$d*.out.log | head -1); E="${O%.out.log}.err.log"
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth $d --out $R/d$d.txt >> $R/run.txt 2>&1
  echo "$(date +%T) d$d CUDA error lines: $(grep -ciE 'cuda error' "$E")" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
