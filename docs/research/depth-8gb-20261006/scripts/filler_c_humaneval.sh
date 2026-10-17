#!/usr/bin/env bash
source /c/bonsai/8gb/preempt_lib.sh   # yield the GPU to queued jobs
# Default sweep C: HumanEval 164 medium on the shipped preset (quality variance over time).
cd /c/bonsai/8gb; D=receipts/filler/humaneval_$(date +%m%d_%H%M); mkdir -p $D
L='C:/bonsai/bonsai-ada-surgery/start-server-262test.ps1'; B=$(cat receipts/newest_bin 2>/dev/null || echo bin-lookup)
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag fill_humaneval -Launcher "$L" -Vars "BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/$B;BONSAI_LAYER=0;BONSAI_LOOKUP=1" >/dev/null 2>&1
for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
(cd /c/bonsai/bonsai-ada-surgery && exec python bench/humaneval_run.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --arm medium --temp 0 --max-tokens 20480 < /dev/null > /c/bonsai/8gb/$D/humaneval.txt 2>&1) &
HP=$!
# yield: a queued job stops the run (partial results stay in humaneval.txt)
while kill -0 $HP 2>/dev/null; do [ -n "$(ls /c/bonsai/8gb/queue/pending 2>/dev/null)" ] && { kill $HP; echo "yield to queue" > /c/bonsai/8gb/$D/yield.txt; break; }; sleep 30; done
cd /c/bonsai/8gb && powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
