#!/usr/bin/env bash
# P148 (#105 23:38Z ask: the only end-to-end quality test of the shipped D26h setup with auto CHOOSING sparse): 245k, q3_0,
# engine product-0059 ab9481005 (bin-d26h), launcher #126 7f16808 test copy. Arms: auto (launcher defaults: auto, q3_0 FRAC 1/4,
# the calib file P146 wrote) vs dense (BONSAI_SPARSE=0). Fresh server per test. Sets: code_needle n 20 (copies), needle_depth n 24,
# needle_depth n 28 (positions other than the n 24 set).
# Gate (declared here, before the run): auto = dense item by item on all three sets (needles strict; copies as printed, lenient if
# strict differs only by whitespace); misses listed per item with position_frac. The auto arm's engine log must show which choice
# the 245k bands got: if auto picked dense there, the result tests nothing new and a forced arm (BONSAI_SPARSE=1, same 1/4 budget)
# runs on the same three sets, and the post says so.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p148; mkdir -p $R
BIN='C:/bonsai/bonsai-ada-surgery/bin-d26h'; L='C:/bonsai/bonsai-ada-surgery/start-server-d26htest.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
CALU=$(cygpath -u "$LOCALAPPDATA/bonsai/sparse-calib.txt"); cp "$CALU" $R/calib_before.txt 2>/dev/null || echo "(no calib file)" > $R/calib_before.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p148_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p148_$1*.out.log 2>/dev/null | head -1); [ -n "$O" ] && grep -hE "^(kv|window) " "$O" > $R/$1.launcher.txt
  echo "$O" > $R/$1.logpath; }
engine() { O=$(cat $R/$1.logpath); grep -iE "sparse|demot|calib|band" "${O%.out.log}.err.log" | grep -v "get_availabl" | tail -60 > $R/$1.engine.txt; }
runsets() { arm=$1; VA=$2
  serve ${arm}_code "$VA"; PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 20 --tag ${arm}_245000 --out $R/code.jsonl > $R/${arm}_code.txt 2>&1; engine ${arm}_code
  serve ${arm}_n24 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag ${arm}_245000 --out $R/needle24.jsonl > $R/${arm}_n24.txt 2>&1; engine ${arm}_n24
  serve ${arm}_n28 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 28 --tag ${arm}_245000 --out $R/needle28.jsonl > $R/${arm}_n28.txt 2>&1; engine ${arm}_n28; }
runsets auto "$V"
runsets dense "$V;BONSAI_SPARSE=0"
cp "$CALU" $R/calib_after.txt 2>/dev/null
# forced arm only if the auto arm never ran sparse at 245k: no "keeps N of M pages" lines (ggml_cuda_fa_sparse_mask) in its
# engine logs. The one early "needs an f16 mask ...; off" line is not a fault: it also appears in P143 runs where sparse ran.
if ! cat $R/auto_*.engine.txt | grep -qE "keeps [0-9]+ of [0-9]+ page"; then echo "auto showed no sparse choice: forced arm runs" > $R/forced_reason.txt; runsets forced "$V;BONSAI_SPARSE=1"; fi
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for arm in auto dense forced; do [ -f $R/${arm}_code.txt ] || continue; echo "== $arm: code $(tail -1 $R/${arm}_code.txt) | n24 $(tail -1 $R/${arm}_n24.txt) | n28 $(tail -1 $R/${arm}_n28.txt)"; cat $R/${arm}_code.launcher.txt; done
  cat $R/forced_reason.txt 2>/dev/null
  python -c "
import json
for f in ('receipts/p148/code.jsonl','receipts/p148/needle24.jsonl','receipts/p148/needle28.jsonl'):
    try:
        for l in open(f):
            r=json.loads(l)
            if not r.get('ok', True): print('MISS', f.split('/')[-1], r.get('tag'), r.get('file'), r.get('fn') or r.get('key') or r.get('fact'), r.get('position_frac'))
    except FileNotFoundError: pass
"; echo "== calib before"; cat $R/calib_before.txt; echo "== calib after"; cat $R/calib_after.txt; } > $R/summary.txt
