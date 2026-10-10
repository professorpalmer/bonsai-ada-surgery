@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CUDA_PATH=C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
"%CUDA_PATH%\bin\nvcc.exe" -O2 -arch=sm_89 -o "%~dp0ballast.exe" "%~dp0ballast.cu" -L"%CUDA_PATH%\lib\x64" -lcudart
