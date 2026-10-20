#!/usr/bin/env bash
# P219 (G2 for V-only 2-bit KV after P218's G1 pass: 64k PPL +0.55 % vs q3_0): retrieval at 245k. r6fake = main's launcher +
# bins kv-fake2v 37a51194f (product-0069 + 0070 + the fake-bits hook with the V-only switch). BONSAI_CTK=q4_0 (the container),
# defaults otherwise (replay off), arms in one block: q4 = real q4_0; v2 = q4_0 with V rows faked to 2-bit uniform (rot on);
# null = q4 with GGML_CUDA_FA_CHUNK=16384 (a rounding-only change). Per arm: needle n24 at 245k, then the P170 code set.
# Gate (declared before the run): v2's confident-wrong answers where q4 is right <= null's count and <= 1 (n24 + code together);
# ok counts reported.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p219; mkdir -p $R
L=$(cygpath -w r6fake/start-server.ps1); KEY=$(cygpath -w r6fake/artifacts/api_key.txt)
for arm in q4 v2 null; do
  V="BONSAI_CTK=q4_0"
  case $arm in v2) V="$V;GGML_CUDA_KV_FAKE_BITS=2;GGML_CUDA_KV_FAKE_V_ONLY=1";; null) V="$V;GGML_CUDA_FA_CHUNK=16384";; esac
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p219_$arm" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p219_$arm*.out.log | head -1); E="${O%.out.log}.err.log"
  grep -hE "^(window|kv +tiered)" "$O" | sed "s/^/$arm: /" >> $R/run.txt
  PYTHONUTF8=1 python benchx/needle_depth.py --key-file "$KEY" --depth 245000 --n 24 --tag p219_$arm --out $R/${arm}_n24.jsonl > $R/${arm}_n24.txt 2>&1
  echo "$(date +%T) $arm n24: $(tail -1 $R/${arm}_n24.txt)" >> $R/run.txt
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p219_${arm}_c" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  PYTHONUTF8=1 python p170_drive.py --set code --arm dense --key-file "$KEY" --out $R/${arm}_code.jsonl > $R/${arm}_code.txt 2>&1
  echo "$(date +%T) $arm code ok $(grep -c '"ok": true' $R/${arm}_code.txt) of $(grep -c '"item"' $R/${arm}_code.txt); CUDA error logs $(grep -l 'CUDA error' logs/*p219_${arm}*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - "$(cygpath -w $R)" >> $R/run.txt <<'PY'
import json, os, re, sys
R = sys.argv[1]
def n24(a): return {r['vault']: r for r in (json.loads(l) for l in open(os.path.join(R, a + '_n24.jsonl'), encoding='utf-8'))}
def code(a): return {r['item']: r for r in (json.loads(l) for l in open(os.path.join(R, a + '_code.jsonl'), encoding='utf-8'))}
def wrong(r):
    a = (r.get('answer') or '').lower()
    miss = any(k in a for k in ('not ', 'no ', "doesn't", 'does not', 'cannot', 'unable', 'none'))
    return (not r['ok']) and bool(re.findall(r'\d{2,}', r.get('answer') or '')) and not miss
rn, rc = n24('q4'), code('q4')
for a in ('null', 'v2'):
    n, c = n24(a), code(a)
    w = ['n%d' % k for k in rn if rn[k]['ok'] and wrong(n[k])] + ['c%d' % k for k in rc if rc[k]['ok'] and wrong(c[k])]
    print(a, 'n24 ok', sum(r['ok'] for r in n.values()), 'code ok', sum(r['ok'] for r in c.values()), '| confident wrong where q4 right:', w)
print('q4 n24 ok', sum(r['ok'] for r in rn.values()), 'code ok', sum(r['ok'] for r in rc.values()))
PY
echo "$(date +%T) done" >> $R/run.txt
