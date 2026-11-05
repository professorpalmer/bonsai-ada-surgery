@echo off
rem bundle-20261105 engine (serve/eog-think = a38714c63d + the end-of-generation ban), the release-20261026 build options.
rem Run from any folder: build_beog.cmd <engine worktree> <build folder>
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CUDA_PATH=%LOCALAPPDATA%\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
set CUDAToolkit_ROOT=%CUDA_PATH%
set PATH=%CUDA_PATH%\bin;%CUDA_PATH%\bin\x86_64;%CUDA_PATH%\nvvm\bin;%PATH%
set PY=%LOCALAPPDATA%\Programs\Python\Python312\Scripts
echo === configure
"%PY%\cmake.exe" -S %1 -B %2 -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM="%PY%\ninja.exe" -DGGML_CUDA=ON "-DCMAKE_CUDA_ARCHITECTURES=75-real;86-real;89-real;89-virtual" -DLLAMA_CURL=OFF -DGGML_RPC=OFF -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe" || exit /b 1
echo === build
"%PY%\cmake.exe" --build %2 --target llama-server test-backend-ops llama-bench llama-perplexity mtmd -j 16 || exit /b 1
echo === done
