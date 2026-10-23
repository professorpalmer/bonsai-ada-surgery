#!/usr/bin/env bash
# BonsaiJob: P228 = post-zip check of bundle-20261022 (the approximate-length note in the layer) on the RTX 2060 SUPER, #233.
# Zip SHA 19dd04ed... = GitHub digest. Published model file: models-hf1022 q4head (template 9,311). BONSAI_8GB=1 + BONSAI_MODEL;
# layer ON (runtime copied from serve-1019c: the same fetch_runtime.ps1 URL + SHA). Requests go to the layer (:8080) with NO note in
# the text (arm L): the layer must add it. Seeds 8 and 9, the 7 note prompts (14 requests). Stock clocks.
# Gates (declared before the run), against P227 on the same 14 cells:
#   L1 (changed before results, #233 6356556420): 14 "approximate-length note on 1 writing request(s)" lines in release_1022/x/logs/layer.log
#   L2 total wall <= 0.7x P227 M (4,444.5 s -> <= 3,111 s)
#   L3 median numbered words <= 10; budget closes 0
#   L4 0 empty texts, write_file 8 / 8 on the save prompts, 0 cut at the output cap, 0 count leaks, 0 false save claims, 0 CUDA errors
cd /c/bonsai/8gb; R=receipts/p228; mkdir -p $R
echo "p228 start $(date +%T)" >> receipts/jobrun.log
Q4=C:/bonsai/models-hf1022/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 10
nvidia-smi --query-gpu=name,driver_version,power.limit,clocks.max.memory,clocks.max.graphics --format=csv > $R/gpu.txt
powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p228 -Launcher 'C:\bonsai\8gb\release_1022\x\start-server.ps1' -Vars "BONSAI_8GB=1;BONSAI_MODEL=$Q4" >> $R/run.txt 2>&1
K=C:/bonsai/8gb/release_1022/x/artifacts/api_key.txt
for i in $(seq 1 120); do curl -s -m 3 -H "Authorization: Bearer $(tr -d '\r\n' < $K)" localhost:8080/v1/models | grep -q bonsai && break; sleep 5; done
echo "$(date +%T) models $(curl -s -H "Authorization: Bearer $(tr -d '\r\n' < $K)" localhost:8080/v1/models | head -c 120)" >> $R/run.txt
curl -s -H "Authorization: Bearer $(tr -d '\r\n' < $K)" localhost:18080/props | python -I -c "import json,sys;d=json.load(sys.stdin);t=d.get('chat_template') or '';print('props chat_template', len(t), 'chars; operating_rules', 'operating_rules' in t)" >> $R/run.txt 2>&1
L=$(ls -t logs/*-p228.out.log | head -1); E=${L%.out.log}.err.log
grep -E "^(8gb|model|window|kv |spec|listen|layer)" $L >> $R/run.txt
PYTHONUTF8=1 python p228_layer.py http://127.0.0.1:8080 $K C:/bonsai/8gb/$R/out > $R/apc.out 2>&1
echo "$(date +%T) runner exit $? ; runs $(wc -l < $R/out/runs.jsonl)" >> $R/run.txt
echo "CUDA error lines: $(cat $L $E | grep -c 'CUDA error')" >> $R/run.txt
echo "spill lines: $(cat $L $E | grep -ci 'spill')" >> $R/run.txt
cp $L $E $R/ 2>/dev/null
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'bonsai_layer\.py' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
echo "p228 end $(date +%T)" >> receipts/jobrun.log
