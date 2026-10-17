#!/usr/bin/env bash
# P156d (13:55): Q2 of T2a-2 only (the 245k items, t2 vs default on bin-t2). P156c ran Q1 (re-read, PASS) and Q3 (cold 245k
# 1,707.1 -> 1,488.6 s, 1.147x: PASS) and was stopped by hand at the start of Q2, so P158 (slot restore + MTP, the demo
# blocker the 4070 waits on) and the T3 probe run first. Q2 as declared in P156: n 20 / n 24 / n 28 at 245k, fresh server per
# test, item by item equal.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p156d; mkdir -p $R
S=/c/bonsai/bonsai-ada-surgery; B=$S/bin-t2; E=$S/artifacts/eval
M=$S/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf
BIN='C:/bonsai/bonsai-ada-surgery/bin-t2'; L='C:/bonsai/bonsai-ada-surgery/start-server-1016test.ps1'
V="BONSAI_BIN=$BIN;BONSAI_LAYER=0"; T="$V;GGML_CUDA_FA_PREFILL_NCOLS2=2"
# Q2
KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p156d_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
for arm in def t2; do VA="$V"; [ $arm = t2 ] && VA="$T"
  serve ${arm}_code "$VA"; PYTHONUTF8=1 python benchx/code_needle.py --key-file $KEY --depth 245000 --n 20 --tag ${arm}_245000 --out $R/code.jsonl > $R/${arm}_code.txt 2>&1
  serve ${arm}_n24 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag ${arm}_245000 --out $R/needle24.jsonl > $R/${arm}_n24.txt 2>&1
  serve ${arm}_n28 "$VA"; PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 28 --tag ${arm}_245000 --out $R/needle28.jsonl > $R/${arm}_n28.txt 2>&1
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - <<'PY' >> $R/summary.txt
import json
for f in ('code', 'needle24', 'needle28'):
    rows = [json.loads(l) for l in open(f'receipts/p156d/{f}.jsonl') if '"ok"' in l]
    by = {}
    for r in rows:
        k = (r.get('file'), r.get('fn') or r.get('vault'), r.get('position_frac'))
        by.setdefault(r['tag'].split('_')[0], {})[k] = r['ok']
    d, t = by.get('def', {}), by.get('t2', {})
    diff = [k for k in set(d) | set(t) if d.get(k) != t.get(k)]
    print(f, 'def', sum(d.values()), '/', len(d), 't2', sum(t.values()), '/', len(t), 'item diffs', diff)
PY
