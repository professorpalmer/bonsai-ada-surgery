#!/usr/bin/env bash
# P144 (#105, the card's quality receipt): exact code copies (n 20) and needles (n 24) at 245k with the SHIPPED setup:
# bundle-20261015 zip bins, release launcher defaults (q3_0 K/V on 8 GB), dense (default) vs BONSAI_SPARSE=1 (budget
# max(12288, host tail x 0.125)). Fresh server per test. (P141 did this with q4_0 on bundle-20261014.)
# Gate (declared here, before the run): sparse = dense on every item (strict); misses listed per item (file / fn / position);
# if a miss lies inside the VRAM line, it is reported as such (sparse cannot drop those cells).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p144; mkdir -p $R
[ -d release_1015/x ] || { echo "no release_1015/x (P142 extracts it)" > $R/summary.txt; exit 1; }
BIN=$(cd "$(dirname "$(find release_1015/x -name llama-server.exe | head -1)")" && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-1015test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p144_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p144_$1*.out.log 2>/dev/null | head -1); [ -n "$O" ] && grep -hE "^(kv|window) |VRAM line|budget" "$O" > $R/$1.launcher.txt; }
for arm in dense sparse; do
  VA="$V"; [ $arm = sparse ] && VA="$V;BONSAI_SPARSE=1"
  serve ${arm}_code "$VA"
  PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 20 --tag ${arm}_245000 --out $R/code.jsonl > $R/${arm}_code.txt 2>&1
  serve ${arm}_needle "$VA"
  PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag ${arm}_245000 --out $R/needle.jsonl > $R/${arm}_needle.txt 2>&1
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for arm in dense sparse; do echo "== $arm: code $(tail -1 $R/${arm}_code.txt) | needles $(tail -1 $R/${arm}_needle.txt)"; cat $R/${arm}_code.launcher.txt 2>/dev/null; done
  python -c "
import json
for f in ('receipts/p144/code.jsonl','receipts/p144/needle.jsonl'):
    try:
        for l in open(f):
            r=json.loads(l)
            if not r.get('ok', True): print('MISS', f.split('/')[-1], r.get('tag'), r.get('file'), r.get('fn') or r.get('key') or r.get('fact'), r.get('position_frac'))
    except FileNotFoundError: pass
"; } > $R/summary.txt
