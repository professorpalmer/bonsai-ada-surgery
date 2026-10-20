#!/usr/bin/env bash
cd /c/bonsai/8gb
echo "$(date +%T) build kv-fake2v HEAD (-j 4)" >> receipts/build_ahead.log
cmd //c 'C:\bonsai\bonsai-ada-surgery\tooling\build-q3kv\build.bat' > logs/build-fake2v.log 2>&1
rc=$?
B=/c/bonsai/bonsai-ada-surgery/tooling/build-q3kv/bin
if [ $rc -eq 0 ] && [ -f $B/llama-server.exe ]; then
  D=/c/bonsai/bonsai-ada-surgery/bin-fake2v; rm -rf $D; mkdir -p $D; cp $B/*.exe $B/*.dll $D/ 2>/dev/null
  cp -n /c/bonsai/bonsai-ada-surgery/bin-q3sparse/*.dll $D/ 2>/dev/null
  echo "$(date +%T) fake2v exit 0" >> receipts/build_ahead.log
else echo "$(date +%T) fake2v exit 1 (rc $rc)" >> receipts/build_ahead.log; fi
