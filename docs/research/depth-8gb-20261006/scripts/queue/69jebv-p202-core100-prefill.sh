#!/usr/bin/env bash
# P202 (after P201: 215 W alone gives +1.3-1.8 % because the SM clock stays on the V-F curve at ~1,875 MHz): Afterburner slot 3
# = PowerLimit 122 (215 W) + core +100, fan 100 % (installed since 10-06; stable and exact for decode then, P4 / P9); slot 5 =
# stock. Core offsets can fail silently, so the identity gate matters most here. Profiles switch only with no server running (P39c). The product zip bins (bundle-20261017), the 1017
# launcher copy, layer off, line pinned 80,640, fresh server per arm. Arms: S1, W1, S2, W2 (each: det_answer 4k + a cold 64k
# read), then W3 and S3 (a cold 245k-class read each, P170 code set item 1 via p170_drive --only 1, for heat over ~20 min).
# Gates (declared before the run): identity: the det 4k hash is equal in every arm (and = P201 d72631aab936fc4e); applied: 215 W in W arms
# and 175 W in S arms, SM median in W at least +60 MHz over S (else the offset did not apply); speed: mean W 64k beats S by > the S spread; heat: max
# GPU temp < 85 C in every arm; 0 CUDA errors. The card ends on slot 5 (stock) whatever happens.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p202; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$ZIP;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640"
stock() { schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6; }
watts() { schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 6; }
trap 'powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; stock' EXIT
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; sleep 3
arm() { # $1 tag, $2 S|W, $3 what
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1; sleep 3
  if [ $2 = W ]; then watts; else stock; fi
  PL=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | tr -d ' \r' | cut -d. -f1)
  if { [ $2 = W ] && [ "$PL" -lt 210 ]; } || { [ $2 = S ] && [ "$PL" -gt 180 ]; }; then
    sleep 5; if [ $2 = W ]; then watts; else stock; fi
    PL=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits | tr -d ' \r' | cut -d. -f1)
  fi
  echo "$(date +%T) $1 ($2): power.limit $PL W" >> $R/run.txt
  ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=power.draw,clocks.sm,temperature.gpu,utilization.gpu,clocks_throttle_reasons.active --format=csv,noheader,nounits)"; sleep 2; done ) > $R/$1.trace.txt & TP=$!
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p202_$1" -Launcher "$L" -Vars "$V" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p202_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  if [ "$3" = short ]; then
    PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/$1_d4.txt >> $R/run.txt 2>&1
    PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 64000 --salt p202_$1 >> $R/run.txt 2>&1
  else
    PYTHONUTF8=1 python p170_drive.py --set code --arm dense --only 1 --key-file $KEY --out $R/$1_long.jsonl > $R/$1_long.txt 2>&1
    echo "$(date +%T) $1 long: $(grep -m1 '"item"' $R/$1_long.txt | cut -c1-260)" >> $R/run.txt
  fi
  kill $TP
  python -c "
import sys
rows = [l.split(' ', 1)[1].split(',') for l in open(sys.argv[1]) if l.count(',') >= 4]
busy = [r for r in rows if float(r[3]) >= 90]
if busy:
    w = sorted(float(r[0]) for r in busy); c = sorted(float(r[1]) for r in busy); t = [float(r[2]) for r in busy]
    print(sys.argv[2], 'busy samples', len(busy), 'power median', w[len(w)//2], 'W; SM median', c[len(c)//2], 'MHz; temp max', max(t), 'C')
" $R/$1.trace.txt $1 >> $R/run.txt
  echo "$(date +%T) $1 CUDA error lines: $(grep -ciE 'cuda error' "$E")" >> $R/run.txt
}
arm S1 S short; arm W1 W short; arm S2 S short; arm W2 W short; arm W3 W long; arm S3 S long
python -c "
import hashlib, sys
h = {a: hashlib.sha256(open(sys.argv[1] + '/' + a + '_d4.txt', 'rb').read()).hexdigest()[:16] for a in ('S1', 'W1', 'S2', 'W2')}
print('identity', h, 'PASS' if len(set(h.values())) == 1 else 'FAIL')
" $R >> $R/run.txt
echo "$(date +%T) done (card back on slot 5 by the exit trap)" >> $R/run.txt
