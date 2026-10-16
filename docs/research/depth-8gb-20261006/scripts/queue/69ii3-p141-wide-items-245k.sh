#!/usr/bin/env bash
# P141 (#21, R10 on the 2060): a wider item set for the shipped sparse rule. bundle-20261014 zip bins (release_1014/x/bin),
# launcher test copy of bfae9143. 245k: code_needle --n 20 and needle_depth --n 24, dense (default) vs BONSAI_SPARSE=1 (shipped:
# 12288 floor, FRAC 1/16), one fresh server per test. The rig's item set differs from the 4070's (its own pycode.raw).
# [Added before the run, 4070 request 04:30Z after R10 missed _check_tzname at 245k on their set: a third arm sparse8 =
# BONSAI_SPARSE=1 + GGML_CUDA_FA_SPARSE_FRAC=0.125, and decode speed 160k -> 245k for sparse16 and sparse8 in this session.]
# Gate (declared here, before the run; = R10 / PR #95 rule): per item vs dense for sparse16 and sparse8; FRAC 1/8 qualifies if it
# equals dense on every item and keeps >= 1.5x of dense decode at 160k and 245k (dense: P135 10.6 / P139 6.2, same bins family).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p141; mkdir -p $R
BIN=$(cd "$(dirname "$(find release_1014/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-1014test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p141_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
for arm in dense sparse sparse8; do
  VA="$V"; [ $arm = sparse ] && VA="$V;BONSAI_SPARSE=1"; [ $arm = sparse8 ] && VA="$V;BONSAI_SPARSE=1;GGML_CUDA_FA_SPARSE_FRAC=0.125"
  serve ${arm}_code "$VA"
  PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 20 --tag ${arm}_245000 --out $R/code.jsonl > $R/${arm}_code.txt 2>&1
  serve ${arm}_needle "$VA"
  PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag ${arm}_245000 --out $R/needle.jsonl > $R/${arm}_needle.txt 2>&1
done
arm() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $R/$1.trace.txt & MP=$!
  bash run_arm.sh $R "$@"; kill $MP
  awk -F", " '{split($1,a," "); v=$2+0; if (v>4000000) v-=4194304; if (NR==1||v<m) {m=v; t=a[1]}} END{print "trace min free", m, "MiB at", t, "over", NR, "samples"}' $R/$1.trace.txt >> $R/$1.txt; }
arm spd_sparse16 "$V;BONSAI_SPARSE=1" "$L" "160000 245000"
arm spd_sparse8 "$V;BONSAI_SPARSE=1;GGML_CUDA_FA_SPARSE_FRAC=0.125" "$L" "160000 245000"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for a in spd_sparse16 spd_sparse8; do echo "== $a"; grep -E "depth|mean decode|trace min" $R/$a.txt | sed -E 's/ttft +[0-9.]+s +//'; done
  for arm in dense sparse sparse8; do echo "== $arm: code $(tail -1 $R/${arm}_code.txt) | needles $(tail -1 $R/${arm}_needle.txt)"; done
  python -c "
import json
for f in ('receipts/p141/code.jsonl','receipts/p141/needle.jsonl'):
    try:
        for l in open(f):
            r=json.loads(l)
            if not r.get('ok', True): print('MISS', f.split('/')[-1], r.get('tag'), r.get('file'), r.get('fn') or r.get('key') or r.get('fact'), r.get('position_frac'))
    except FileNotFoundError: pass
"; } > $R/summary.txt
