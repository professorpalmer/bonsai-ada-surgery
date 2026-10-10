@echo off
rem Build decode_trace.exe against an engine build (default %TEMP%\wt-0045 + %TEMP%\build-0045) and the pip CUDA 13 headers.
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
if "%SRC%"=="" set SRC=%TEMP%\wt-0045
if "%BLD%"=="" set BLD=%TEMP%\build-0045
set CUDA=C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
cl /nologo /O2 /EHsc /std:c++17 /I"%SRC%\include" /I"%SRC%\ggml\include" /I"%CUDA%\include" "%~dp0decode_trace.cpp" /Fe"%BLD%\bin\decode_trace.exe" /Fo"%BLD%\decode_trace.obj" /link "%BLD%\src\llama.lib"
