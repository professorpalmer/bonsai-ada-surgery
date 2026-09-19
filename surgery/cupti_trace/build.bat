@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
set CU=C:\Users\pwall\AppData\Local\Programs\Python\Python312\Lib\site-packages\nvidia\cu13
cd /d %~dp0
cl /nologo /O2 /EHsc /std:c++17 /LD /I"%CU%\include" cupti_trace.cpp /link /OUT:cupti_trace.dll kernel32.lib
