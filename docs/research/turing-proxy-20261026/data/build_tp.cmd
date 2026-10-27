@echo off
set "PATH=%PATH%;C:\Program Files (x86)\Microsoft Visual Studio\Installer"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set NVCC=<nvcc 13.4>
echo === tp-p4 configure %TIME%
cmake -S <projects>\wt-rel1026 -B <projects>\build-tp-p4 -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=OFF "-DCMAKE_CUDA_FLAGS=-gencode=arch=compute_75,code=sm_89" -DCMAKE_CUDA_COMPILER=%NVCC% -DLLAMA_CURL=OFF || exit /b 1
echo === tp-p4 build %TIME%
cmake --build <projects>\build-tp-p4 --config Release --target test-backend-ops llama-bench llama-perplexity -j 16 || exit /b 2
echo === tp-null configure %TIME%
cmake -S <projects>\wt-pkqnull -B <projects>\build-tp-null -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=OFF "-DCMAKE_CUDA_FLAGS=-gencode=arch=compute_75,code=sm_89" -DCMAKE_CUDA_COMPILER=%NVCC% -DLLAMA_CURL=OFF || exit /b 3
echo === tp-null build %TIME%
cmake --build <projects>\build-tp-null --config Release --target test-backend-ops llama-bench llama-perplexity -j 16 || exit /b 4
echo === done %TIME%
