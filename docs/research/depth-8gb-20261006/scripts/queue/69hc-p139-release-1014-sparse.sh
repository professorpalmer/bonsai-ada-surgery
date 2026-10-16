#!/usr/bin/env bash
# P139 (R06 on the published zip, sparse part): bundle-20261014 zip bins (release_1014/x/bin, from P138), launcher test copy of
# bfae9143. (1) 245k cold, dense (default) vs BONSAI_SPARSE=1, 10 s trace; (2) 245k exact copies (10) and needles (12) with
# BONSAI_SPARSE=1 (dense on the same items: P136, 10/10 + 12/12); (3) HumanEval 164 on the zip bins, default switches.
# Gates (declared here, before the run): 245k sparse >= 1.8x dense; trace min free >= 60 MiB in both arms; sparse 245k copies
# 10/10 and needles 12/12 (= dense P136); HumanEval >= 157/164; 0 one-token.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p139; mkdir -p $R
[ -d release_1014/x ] || { echo "no release_1014/x (P138 extracts it)" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$(find release_1014/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-1014test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
arm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.trace.txt & MP=$!
  bash run_arm.sh $R "$@"; kill $MP
  awk -F", " '{split($1,a," "); v=$2+0; if (v>4000000) v-=4194304; if (NR==1||v<m) {m=v; t=a[1]}} END{print "trace min free", m, "MiB at", t, "over", NR, "samples"}' $R/$1.trace.txt >> $R/$1.txt
  E=$(ls -t logs/*-$1.err.log | head -1); O="${E%err.log}out.log"; grep -hE "^(kv|8gb|window) |VRAM line" "$O" > $R/$1.launcher.txt; }
arm dense245 "$V" "$L" "245000"
arm sparse245 "$V;BONSAI_SPARSE=1" "$L" "245000"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p139_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
serve sparse_code "$V;BONSAI_SPARSE=1"
PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 10 --tag sparse_245000 --out $R/code.jsonl > $R/sparse_code_245000.txt 2>&1
serve sparse_needle "$V;BONSAI_SPARSE=1"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 12 --tag sparse_245000 --out $R/needle.jsonl > $R/sparse_needle_245000.txt 2>&1
serve humaneval "$V"
cd /c/bonsai/bonsai-ada-surgery && python bench/humaneval_run.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --arm medium --temp 0 --max-tokens 20480 < /dev/null > /c/bonsai/8gb/$R/humaneval.txt 2>&1
cd /c/bonsai/8gb && powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for a in dense245 sparse245; do f=$R/$a.txt; echo "== $a: $(grep -c '(1 tok)' $f) one-token"; cat $R/$a.launcher.txt; grep -E "loaded|depth|mean decode|did not|trace min" $f | sed -E 's/ttft +[0-9.]+s +//'; done
  echo "== sparse 245k: code $(tail -1 $R/sparse_code_245000.txt) | needles $(tail -1 $R/sparse_needle_245000.txt)"
  echo "== humaneval: $(grep -E 'pass@1' $R/humaneval.txt)"; grep -E "FAIL" $R/humaneval.txt | awk '{print $2}' | tr '\n' ' '; echo; } > $R/summary.txt
