@echo off
set "PATH=%PATH%;C:\Program Files (x86)\Microsoft Visual Studio\Installer"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set NVCC=<nvcc 13.4>
call :one E "-DGGML_FA_D256_C64_QREG=false"
call :one B "-DGGML_FA_D256_C64_NB=64 -DGGML_FA_D256_C64_QREG=false"
call :one C "-DGGML_FA_D256_C64_NB=64 -DGGML_FA_D256_C64_OCC=1"
echo === done
goto :eof
:one
echo === cfg%1 configure (%~2)
cmake -S <projects>\wt-cfg -B <projects>\build-cfg%1 -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89-real "-DCMAKE_CUDA_FLAGS=%~2" -DCMAKE_CUDA_COMPILER=%NVCC% -DLLAMA_CURL=OFF
echo === cfg%1 build
cmake --build <projects>\build-cfg%1 --config Release --target test-backend-ops llama-bench llama-perplexity -j 16
goto :eof
