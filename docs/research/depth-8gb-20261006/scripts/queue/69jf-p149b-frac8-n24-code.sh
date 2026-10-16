#!/usr/bin/env bash
# P149b (the rest of P149, after P150; P149 stopped after its n 28 set so the bundle-20261016 check runs first) (#105 04:43Z ask, not blocking the release): is the 4070's vault-16 loss at FRAC 1/8 card-independent? 245k, q3_0, bin-d26h
# (ab9481005) + #126 7f16808 test copy, FORCED sparse (BONSAI_SPARSE=1) at GGML_CUDA_FA_SPARSE_FRAC=0.125, fresh server per test:
# needle_depth n 28 first (the ask), then n 24 and code_needle n 20 on this engine (P144 ran those on bundle-20261015).
# Compared item by item with P148's dense arm (same engine, same sets). Rule (declared here, before the run): 1/8 = dense on all three
# sets -> the rigs disagree, look closer; 1/8 loses an item dense keeps (vault 16 or another) -> 1/4 stands.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p149; mkdir -p $R
BIN='C:/bonsai/bonsai-ada-surgery/bin-d26h'; L='C:/bonsai/bonsai-ada-surgery/start-server-d26htest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
CALU=$(cygpath -u "$LOCALAPPDATA/bonsai/sparse-calib.txt"); cp "$CALU" $R/calib_before.txt 2>/dev/null || echo "(no calib file)" > $R/calib_before.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p149_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p149_$1*.out.log 2>/dev/null | head -1); [ -n "$O" ] && grep -hE "^(kv|window) " "$O" > $R/$1.launcher.txt
  echo "$O" > $R/$1.logpath; }
engine() { O=$(cat $R/$1.logpath); grep -iE "sparse|demot|calib|band" "${O%.out.log}.err.log" | grep -v "get_availabl" | tail -60 > $R/$1.engine.txt; }
runsets() { arm=$1; VA=$2
  serve ${arm}_code "$VA"; PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 20 --tag ${arm}_245000 --out $R/code.jsonl > $R/${arm}_code.txt 2>&1; engine ${arm}_code
  serve ${arm}_n24 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag ${arm}_245000 --out $R/needle24.jsonl > $R/${arm}_n24.txt 2>&1; engine ${arm}_n24
  serve ${arm}_n28 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 28 --tag ${arm}_245000 --out $R/needle28.jsonl > $R/${arm}_n28.txt 2>&1; engine ${arm}_n28; }
arm=f8; VA="$V;BONSAI_SPARSE=1;GGML_CUDA_FA_SPARSE_FRAC=0.125"
serve ${arm}_n24 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag ${arm}_245000 --out $R/needle24.jsonl > $R/${arm}_n24.txt 2>&1; engine ${arm}_n24
serve ${arm}_code "$VA"; PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 20 --tag ${arm}_245000 --out $R/code.jsonl > $R/${arm}_code.txt 2>&1; engine ${arm}_code
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for arm in f8; do [ -f $R/${arm}_code.txt ] || continue; echo "== $arm: code $(tail -1 $R/${arm}_code.txt) | n24 $(tail -1 $R/${arm}_n24.txt) | n28 $(tail -1 $R/${arm}_n28.txt)"; cat $R/${arm}_code.launcher.txt; done
  cat $R/forced_reason.txt 2>/dev/null
  python -c "
import json
for f in ('receipts/p149/code.jsonl','receipts/p149/needle24.jsonl','receipts/p149/needle28.jsonl'):
    try:
        for l in open(f):
            r=json.loads(l)
            if not r.get('ok', True): print('MISS', f.split('/')[-1], r.get('tag'), r.get('file'), r.get('fn') or r.get('key') or r.get('fact'), r.get('position_frac'))
    except FileNotFoundError: pass
"; echo "== calib before"; cat $R/calib_before.txt; echo "== calib after"; cat $R/calib_after.txt; } > $R/summary.txt
