#!/usr/bin/env bash
# P140 (release-20261014b S05, 2060): the 8 GB q4_0 default unchanged by 0056 + 0057. product-0056 b86298dba (bin-q3sparse from
# P129) vs the bundle-20261014 zip bins (release_1014/x/bin), same launcher (test copy sparsetest2q3 = #49 3035572 + q3_0 cell
# size; default switches, sparse off, q4_0). Same session, alternated x2:
#   (a) fixed answers: lookup_ab.py at depth 0 on a fresh server per arm (22 items), compare the text hashes;
#   (b) speed: quick_tps 64k -> 128k, one server per arm.
# Gate (declared here, before the run): S05 - the answers identical (same sha per item in both rounds; 0057 is meant to be
# bit-exact for q4_0) and decode at 64k / 128k not more than 2 % slower than bundle-20261014 (means of 2 rounds); 0 one-token.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p140; mkdir -p $R
[ -f /c/bonsai/bonsai-ada-surgery/bin-q3sparse/llama-server.exe ] || { echo "no bin-q3sparse (P129 builds it)" > $R/summary.txt; exit 1; }
B14=$(cd /c/bonsai/8gb/release_1014/x/bin && pwd -W)
L='C:/bonsai/bonsai-ada-surgery/start-server-sparsetest2q3.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V14="BONSAI_BIN=$B14;BONSAI_LAYER=0"; V56="BONSAI_BIN=C:/bonsai/bonsai-ada-surgery/bin-q3sparse;BONSAI_LAYER=0"
serve() { powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p140_$1 -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done; }
for r in 1 2; do
  serve ans14_r$r "$V14"; python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag b14_r$r --out $R/ab.jsonl --depth 0 > $R/ans14_r$r.txt 2>&1
  serve ans56_r$r "$V56"; python lookup_ab.py --base http://127.0.0.1:8080 --key-file $KEY --tag b56_r$r --out $R/ab.jsonl --depth 0 > $R/ans56_r$r.txt 2>&1
done
for r in 1 2; do
  bash run_arm.sh $R spd14_r$r "$V14" "$L" "64000 128000"
  bash run_arm.sh $R spd56_r$r "$V56" "$L" "64000 128000"
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
python - > $R/summary.txt <<'PY2'
import json, collections
rows=[json.loads(l) for l in open('receipts/p140/ab.jsonl')]
by=collections.defaultdict(dict)
for r in rows: by[r['item']+'|'+r['kind']][r['tag']]=r['sha']
same=sum(1 for k,v in by.items() if len(set(v.values()))==1); print('answers: items', len(by), 'identical in all 4 runs', same)
for k,v in by.items():
    if len(set(v.values()))>1: print('  DIFF', k, v)
print('one-token (n==1):', sum(1 for r in rows if r.get('n')==1))
PY2
for a in spd14_r1 spd56_r1 spd14_r2 spd56_r2; do echo "== $a: $(grep -c '(1 tok)' $R/$a.txt) one-token"; grep -E "loaded|mean decode|did not" $R/$a.txt; done >> $R/summary.txt
