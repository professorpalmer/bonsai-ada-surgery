#!/usr/bin/env bash
# P136 (#21 / R06 pre-run): exact code copies (10) and needles (12) at 200k and 245k on the release candidate (bin-rc55 from P135,
# launcher #49 3035572 test copy): dense (default) vs BONSAI_SPARSE=1 (budget max(8192, host tail / 16)). Fresh server per test.
# Rewritten before the run (2026-10-14 08:2x): launcher #49 is now 3035572 (BONSAI_SPARSE=1 sets the floor B 12288, engine
# keeps max(B, host tail / 16); sparse headroom 64 MiB). Arms: dense (default, off) and sparse (BONSAI_SPARSE=1), at 160k, 200k
# and 245k (the R06 item 2 set). The 8192-floor case is the 4070's R04 (failed at 200k), not repeated here.
# Gate (declared here, before the run; R06): sparse copies and needles equal to dense at 160k, 200k and 245k; per-item misses listed.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p136; mkdir -p $R
[ -f /c/bonsai/bonsai-ada-surgery/bin-rc55/llama-server.exe ] || { echo "no bin-rc55 (P135 builds it)" > $R/summary.txt; exit 1; }
L='C:/bonsai/bonsai-ada-surgery/start-server-rc55.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/bin-rc55;BONSAI_LAYER=0"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p136_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p136_$1*.out.log 2>/dev/null | head -1); [ -n "$O" ] && grep -hE "^kv |VRAM line" "$O" > $R/$1.launcher.txt; }
for D in 200000 245000 160000; do for arm in dense sparse; do
  VA="$V"; [ $arm = sparse ] && VA="$V;BONSAI_SPARSE=1"
  serve ${arm}_code_$D "$VA"
  PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth $D --n 10 --tag ${arm}_$D --out $R/code.jsonl > $R/${arm}_code_$D.txt 2>&1
  serve ${arm}_needle_$D "$VA"
  PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth $D --n 12 --tag ${arm}_$D --out $R/needle.jsonl > $R/${arm}_needle_$D.txt 2>&1
done; done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
{ for D in 200000 245000 160000; do for arm in dense sparse; do echo "== $arm $D: code $(tail -1 $R/${arm}_code_$D.txt) | needles $(tail -1 $R/${arm}_needle_$D.txt)"; done; done
  python -c "
import json
for f in ('receipts/p136/code.jsonl','receipts/p136/needle.jsonl'):
    try:
        for l in open(f):
            r=json.loads(l)
            if not r.get('ok', True): print('MISS', f.split('/')[-1], r.get('tag'), r.get('file'), r.get('fn') or r.get('key') or r.get('fact'), r.get('position_frac'))
    except FileNotFoundError: pass
"; } > $R/summary.txt
