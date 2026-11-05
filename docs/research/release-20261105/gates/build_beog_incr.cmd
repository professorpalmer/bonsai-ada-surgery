@echo off
rem bundle-20261105 engine, as built: the release-20261026 build folder (its CMake cache = the 1026 release options),
rem source worktree moved from a38714c63d to 21fd9beda (patch 0073 changes only common/), then an incremental build.
rem   git -C <1026 engine worktree> checkout --detach 21fd9beda
rem   build_beog_incr.cmd <1026 build folder>
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CUDA_PATH=%LOCALAPPDATA%\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
set CUDAToolkit_ROOT=%CUDA_PATH%
set PATH=%CUDA_PATH%\bin;%CUDA_PATH%\bin\x86_64;%CUDA_PATH%\nvvm\bin;%PATH%
set PY=%LOCALAPPDATA%\Programs\Python\Python312\Scripts
rem configure again on the same cache: build-info.cpp takes the new commit (CMake did not rerun it by itself)
"%PY%\cmake.exe" %1 || exit /b 1
"%PY%\cmake.exe" --build %1 --target llama-server test-backend-ops llama-bench llama-perplexity mtmd -j 16 || exit /b 1
echo === done
