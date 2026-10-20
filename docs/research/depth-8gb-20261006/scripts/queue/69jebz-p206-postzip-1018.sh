#!/usr/bin/env bash
# P206 (post-zip check of bundle-20261018 on the 2060, not asked; for Cary's serve folder): the zip's own launcher, defaults.
# Gates: zip sha already matched (f8347f4e...); launcher prints the 8gb line; cold 64k within 2 % of P202 stock (306.5-307.4
# tok/s); det_answer 4k = the 17b zip hash in the same block (patch 0067 only stops drafts at the end of an answer); 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p206; mkdir -p $R
KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
for arm in z17b z1018; do
  case $arm in z17b) L=$(cygpath -w release_17b/x/start-server.ps1);; z1018) L=$(cygpath -w release_1018/x/start-server.ps1);; esac
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p206_$arm" -Launcher "$L" -Vars "" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p206_$arm*.out.log | head -1); E="${O%.out.log}.err.log"
  grep -hE "^(8gb|window|kv +tiered|layer)" "$O" | sed "s/^/$arm: /" >> $R/run.txt
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/${arm}_d4.txt >> $R/run.txt 2>&1
  [ $arm = z1018 ] && PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 64000 --salt p206 >> $R/run.txt 2>&1
  echo "$(date +%T) $arm CUDA error lines: $(grep -ciE 'cuda error' "$E")" >> $R/run.txt
done
python -c "
import hashlib, sys
h = {a: hashlib.sha256(open(sys.argv[1] + '/' + a + '_d4.txt', 'rb').read()).hexdigest()[:16] for a in ('z17b', 'z1018')}
print('identity', h, 'PASS' if h['z17b'] == h['z1018'] else 'DIFFERENT')
" $R >> $R/run.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
