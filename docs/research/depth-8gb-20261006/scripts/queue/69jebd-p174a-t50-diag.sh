#!/usr/bin/env bash
# P174a (T5-0 failed in P174: env unset, hashes differ from P169 at 4k and 32k; P174 also set BONSAI_SPARSE=0, P169 did not).
# Split the two factors at 4k (det_answer, fresh server each): A = zip bins + BONSAI_SPARSE=0; B = bin-t5 without BONSAI_SPARSE.
# Expect: A = P174's hash (55d8056e05da9685) and B = P169's (d72631aab936fc4e) if BONSAI_SPARSE=0 is the cause.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p174a; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
T5=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p174a_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p174a_$1*.out.log | head -1); grep -hE "^(kv|spec) " "$O" > $R/$1.launcher.txt
}
serve A "BONSAI_BIN=$ZIP;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/A.txt >> $R/run.txt 2>&1
serve B "BONSAI_BIN=$T5;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640"
PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 4000 --out $R/B.txt >> $R/run.txt 2>&1
python -c "
import hashlib, sys
for a in 'AB': print(a, hashlib.sha256(open(sys.argv[1] + '/' + a + '.txt', 'rb').read()).hexdigest()[:16])
" $R >> $R/run.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
