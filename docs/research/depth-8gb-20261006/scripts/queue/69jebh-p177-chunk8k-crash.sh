#!/usr/bin/env bash
# P177 (P175 S-2 crashed: CUDA error at ~20k tokens with GGML_CUDA_FA_CHUNK=8192 + window, bin-t5s): split the cause with one
# det_answer at 32k each, fresh server: A = zip bins + GGML_CUDA_FA_CHUNK=8192 (no window); B = bin-t5s + 8192 + window +
# GGML_CUDA_FA_CHUNK_SKIP=0; C = bin-t5s + 8192 + window (skip on, = S-2). Report pass / CUDA error per arm.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p177; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
T5S=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5s)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0;GGML_CUDA_FA_CHUNK=8192"
W="LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p177_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p177_$1*.out.log | head -1); E="${O%.out.log}.err.log"
}
for arm in A B C; do
  case $arm in A) V="BONSAI_BIN=$ZIP;$B0";; B) V="BONSAI_BIN=$T5S;$B0;$W;GGML_CUDA_FA_CHUNK_SKIP=0";; C) V="BONSAI_BIN=$T5S;$B0;$W";; esac
  serve $arm "$V"
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 32000 --out $R/$arm.txt >> $R/run.txt 2>&1
  echo "$(date +%T) $arm CUDA error lines: $(grep -ciE 'cuda error' "$E"); $(grep -hiE 'CUDA error|error:' "$E" | head -2 | tr '\n' ' ')" >> $R/run.txt
  grep -h "8gb    preset" "$O" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
