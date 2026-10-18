#!/usr/bin/env bash
# builds the turing-mmq branch with GGML_CUDA_TURING_PTQ1_VARIANT = each argument, into bin-mmqv<N>
cd /c/bonsai/8gb
H=/c/bonsai/bonsai-ada-surgery/vendor/prism-q3kv/ggml/src/ggml-cuda/mmq-turing-variant.h
for v in "$@"; do
  printf '#pragma once\n// experiment knob for mmq-config-turing.cuh (a rebuild of the MMQ files per value)\n#define GGML_CUDA_TURING_PTQ1_VARIANT %s\n' "$v" > $H
  echo "$(date +%T) build mmqv$v (-j 4)" >> receipts/build_ahead.log
  cmd //c 'C:\bonsai\bonsai-ada-surgery\tooling\build-q3kv\build.bat' > logs/build-mmqv$v.log 2>&1
  rc=$?
  B=/c/bonsai/bonsai-ada-surgery/tooling/build-q3kv/bin
  if [ $rc -eq 0 ] && [ -f $B/llama-server.exe ]; then
    D=/c/bonsai/bonsai-ada-surgery/bin-mmqv$v; rm -rf $D; mkdir -p $D; cp $B/*.exe $B/*.dll $D/ 2>/dev/null
    cp -n /c/bonsai/bonsai-ada-surgery/bin-q3sparse/*.dll $D/ 2>/dev/null
    echo "$(date +%T) mmqv$v exit 0" >> receipts/build_ahead.log
  else echo "$(date +%T) mmqv$v exit 1 (rc $rc)" >> receipts/build_ahead.log; fi
done
printf '#pragma once\n// experiment knob for mmq-config-turing.cuh (a rebuild of the MMQ files per value)\n#define GGML_CUDA_TURING_PTQ1_VARIANT 0\n' > $H
