@echo off
rem <projects> = the folder that holds the engine worktree and the build folder; <nvcc 13.4> = the CUDA 13.4 nvcc
set "PATH=%PATH%;C:\Program Files (x86)\Microsoft Visual Studio\Installer"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
echo === p2b configure
cmake -S <projects>\wt-p2b -B <projects>\build-p2b -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON "-DCMAKE_CUDA_ARCHITECTURES=75-real;89-real" "-DCMAKE_CUDA_FLAGS=-DGGML_PKQ_FP16ACC" -DCMAKE_CUDA_COMPILER=<nvcc 13.4> -DLLAMA_CURL=OFF || exit /b 1
echo === p2b build
cmake --build <projects>\build-p2b --config Release --target llama-server test-backend-ops llama-bench llama-perplexity mtmd -j 16
echo === done
