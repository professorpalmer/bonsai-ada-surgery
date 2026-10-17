#!/usr/bin/env bash
# P180 (P178 R-3 gave "////" with dense=15:31:47:63): localize at 4k, where the window changes nothing. bin-t5r3 (hybrid input fix), det_answer 4k:
# A = window 16k (no dense list) -> must equal the dense hash d72631aab936fc4e (or the current drift state, see B);
# B = no window at all (product behavior); C = window 16k + dense=15; D = C with GGML_CUDA_FA_CHUNK_SKIP=0.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p180; mkdir -p $R
for i in $(seq 1 120); do grep -q "t5r3 exit" receipts/build_ahead.log && break; sleep 10; done
T=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r3)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_BIN=$T;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
for arm in A B C D; do
  case $arm in
    A) V="$B0;LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024";;
    B) V="$B0";;
    C) V="$B0;LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024,dense=15";;
    D) V="$B0;LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024,dense=15;GGML_CUDA_FA_CHUNK_SKIP=0";;
  esac
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p180_$arm" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/$arm.txt >> $R/run.txt 2>&1
  echo "$arm head: $(head -c 80 $R/$arm.txt | tr '\n' ' ')" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
