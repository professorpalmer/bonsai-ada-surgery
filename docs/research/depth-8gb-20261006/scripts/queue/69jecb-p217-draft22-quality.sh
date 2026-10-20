#!/usr/bin/env bash
# P217 (quality gate for "replay on + draft 2 / tail 2" on the 8 GB preset, after P215's +22 % decode at 128k): the P170 code set
# (24 inserted constants in ~240k tokens of code; 12 named + 12 described) through the r6test folder (main's launcher + 0069 +
# 0070), BONSAI_RS_REPLAY=1, driver arm "dense" (the full read), in one block:
#   d11  = BONSAI_SPEC 1 / SPEC_DEEP 1 (the reference)
#   null = d11 with GGML_CUDA_FA_CHUNK=16384 (a rounding-only change, as the 4070's null test)
#   d22  = BONSAI_SPEC 2 / SPEC_DEEP 2
# Gate (declared before the run): "confident wrong where d11 is right" for d22 <= that count for null (and <= 1); report all
# changed items, ok counts and cold times.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p217; mkdir -p $R
L=$(cygpath -w r6test/start-server.ps1); KEY=$(cygpath -w r6test/artifacts/api_key.txt)
for arm in d11 null d22; do
  V="BONSAI_RS_REPLAY=1"
  case $arm in d11) V="$V;BONSAI_SPEC=1;BONSAI_SPEC_DEEP=1";; null) V="$V;BONSAI_SPEC=1;BONSAI_SPEC_DEEP=1;GGML_CUDA_FA_CHUNK=16384";; d22) V="$V;BONSAI_SPEC=2;BONSAI_SPEC_DEEP=2";; esac
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p217_$arm" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p217_$arm*.out.log | head -1); E="${O%.out.log}.err.log"
  grep -hE "^(kv +tiered|spec)" "$O" | sed "s/^/$arm: /" >> $R/run.txt
  PYTHONUTF8=1 python p170_drive.py --set code --arm dense --key-file "$KEY" --out $R/$arm.jsonl > $R/$arm.txt 2>&1
  echo "$(date +%T) $arm ok $(grep -c '"ok": true' $R/$arm.txt) of $(grep -c '"item"' $R/$arm.txt); cold $(grep -m1 '"item"' $R/$arm.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s; CUDA error lines $(grep -ciE 'cuda error' "$E")" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - "$(cygpath -w $R)" >> $R/run.txt <<'PY'
import json, os, re, sys
R = sys.argv[1]
def load(a): return {r['item']: r for r in (json.loads(l) for l in open(os.path.join(R, a + '.jsonl'), encoding='utf-8'))}
def wrong(r):
    a = (r.get('answer') or '').lower()
    miss = any(k in a for k in ('not ', 'no ', "doesn't", 'does not', 'cannot', 'unable', 'none'))
    return (not r['ok']) and bool(re.findall(r'-?\d+(?:\.\d+)?', r.get('answer') or '')) and not miss
ref = load('d11')
for a in ('null', 'd22'):
    d = load(a)
    w = sorted(k for k in ref if ref[k]['ok'] and wrong(d[k]))
    ch = sorted(k for k in ref if ref[k]['ok'] != d[k]['ok'])
    print(a, 'ok', sum(r['ok'] for r in d.values()), '| confident wrong where d11 right:', w, '| right/wrong changes:', ch)
PY
echo "$(date +%T) done" >> $R/run.txt
