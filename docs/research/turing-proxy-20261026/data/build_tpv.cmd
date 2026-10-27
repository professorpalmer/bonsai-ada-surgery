@echo off
set "PATH=%PATH%;C:\Program Files (x86)\Microsoft Visual Studio\Installer"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set NVCC=<nvcc 13.4>
for %%R in (16 32 64) do (
  echo === tpv%%R configure %TIME%
  cmake -S <projects>\wt-tpv -B <projects>\build-tpv%%R -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=OFF "-DCMAKE_CUDA_FLAGS=-gencode=arch=compute_75,code=sm_89 -DGGML_CUDA_FA_F16_V_ROWS=%%R" -DCMAKE_CUDA_COMPILER=%NVCC% -DLLAMA_CURL=OFF || exit /b 1
  echo === tpv%%R build
  cmake --build <projects>\build-tpv%%R --config Release --target test-backend-ops llama-bench llama-perplexity -j 16
)
echo === done %TIME%
echo done> <scratchpad>\tproxy\tpv.done
