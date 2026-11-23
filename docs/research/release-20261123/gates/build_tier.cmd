@echo off
rem bundle-20261123 engine (serve/tier-fix = 21fd9beda + tier write-back fix + F1 switch + MMID row bound + host-memory
rem fallback), the release-20261026 build options, from NEUTRAL paths: the compiler sees Y:\bonsai and Y:\build only
rem (assert source paths in the DLLs hold no local user or folder names). Y: = a folder that holds a junction "bonsai"
rem to the engine worktree and the build folder. The web UI comes from the pinned tools\ui\dist in the worktree (no npm,
rem no download); its licence list is licenses\web-ui-THIRD-PARTY.txt.
rem   build_tier.cmd <engine worktree> <neutral folder>
setlocal
if "%~2"=="" (echo usage: build_tier.cmd ^<engine worktree^> ^<neutral folder^> & exit /b 2)
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CUDA_PATH=%LOCALAPPDATA%\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
set CUDAToolkit_ROOT=%CUDA_PATH%
set PATH=%CUDA_PATH%\bin;%CUDA_PATH%\bin\x86_64;%CUDA_PATH%\nvvm\bin;%PATH%
set PY=%LOCALAPPDATA%\Programs\Python\Python312\Scripts
if not exist "%~1\tools\ui\dist\index.html" (echo no pinned tools\ui\dist in the worktree & exit /b 1)
if not exist "%~2" mkdir "%~2"
if not exist "%~2\build" mkdir "%~2\build"
if not exist "%~2\bonsai" mklink /J "%~2\bonsai" "%~1" >nul || exit /b 1
subst Y: /d >nul 2>&1
subst Y: "%~2" || exit /b 1
echo === configure
"%PY%\cmake.exe" -S Y:/bonsai -B Y:/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM="%PY%\ninja.exe" -DGGML_CUDA=ON "-DCMAKE_CUDA_ARCHITECTURES=75-real;86-real;89-real;89-virtual" -DLLAMA_CURL=OFF -DGGML_RPC=OFF -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DCMAKE_CUDA_COMPILER="%CUDA_PATH%\bin\nvcc.exe"
if errorlevel 1 goto fail
echo === build
"%PY%\cmake.exe" --build Y:/build --target llama-server test-backend-ops llama-bench llama-perplexity mtmd test-kv-tier -j 16
if errorlevel 1 goto fail
subst Y: /d
echo === done
exit /b 0
:fail
subst Y: /d
echo === FAIL
exit /b 1
