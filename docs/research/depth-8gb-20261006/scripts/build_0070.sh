#!/usr/bin/env bash
cd /c/bonsai/8gb
echo "$(date +%T) build r6-0070 HEAD (-j 4)" >> receipts/build_ahead.log
cmd //c 'C:\bonsai\bonsai-ada-surgery\tooling\build-q3kv\build.bat' > logs/build-0070.log 2>&1
rc=$?
B=/c/bonsai/bonsai-ada-surgery/tooling/build-q3kv/bin
if [ $rc -eq 0 ] && [ -f $B/llama-server.exe ]; then
  D=/c/bonsai/bonsai-ada-surgery/bin-0070; rm -rf $D; mkdir -p $D; cp $B/*.exe $B/*.dll $D/ 2>/dev/null
  cp -n /c/bonsai/bonsai-ada-surgery/bin-q3sparse/*.dll $D/ 2>/dev/null
  echo "$(date +%T) 0070 exit 0" >> receipts/build_ahead.log
else echo "$(date +%T) 0070 exit 1 (rc $rc)" >> receipts/build_ahead.log; fi
