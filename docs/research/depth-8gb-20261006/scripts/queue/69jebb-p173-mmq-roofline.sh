#!/usr/bin/env bash
# P173 (cold read, the weights part = 516 s of a 245k read on the 2060, ~25 TFLOP/s effective): how fast is the PTQ1_0
# prefill matmul alone on sm_75? test-backend-ops perf, MUL_MAT 4096 x 512 x 14336 (the generic perf case), for PTQ1_0 (MMQ
# int8 tile path at every batch), Q8_0, Q4_0, F16 (cuBLAS), and PTQ1_0 with GGML_CUDA_PTQ1_0_MMQ_MAX_BATCH=256 (the cuBLAS fp16
# fallback at n = 512). Bins: bundle-20261017 zip. No server runs. Reported: GFLOPS per type; nothing ships from this.
cd /c/bonsai/8gb; R=receipts/p173; mkdir -p $R
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; sleep 3
ZIPU="$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")"
T="$ZIPU/test-backend-ops.exe"
[ -f "$T" ] || T=/c/bonsai/bonsai-ada-surgery/bin-t4b/test-backend-ops.exe
echo "$(date +%T) test-backend-ops: $T" > $R/run.txt
"$T" perf -o MUL_MAT -b CUDA0 -p "m=4096,n=512,k=14336" < /dev/null > $R/perf_all.txt 2>&1
grep -E "type_a=(ptq1_0|q8_0|q4_0|f16|tq2_0|tq1_0)," $R/perf_all.txt >> $R/run.txt
GGML_CUDA_PTQ1_0_MMQ_MAX_BATCH=256 "$T" perf -o MUL_MAT -b CUDA0 -p "type_a=ptq1_0.*m=4096,n=512,k=14336" < /dev/null > $R/perf_cublas.txt 2>&1
echo "cuBLAS fallback:" >> $R/run.txt; grep -E "type_a=ptq1_0" $R/perf_cublas.txt >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
