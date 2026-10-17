#!/usr/bin/env bash
# P176 (is the T5 chunk skip bitwise exact?): bin-t5s, window 16k / sink 1k / tail 1k, det_answer at 128k, back to back in one
# block: A = GGML_CUDA_FA_CHUNK_SKIP=0 (mask only), B = skip on (default), C = skip off again (a drift check). Gate: A = B = C
# sha256 (if A = C but B differs, the skip is not exact). Also the cold times (A / C mask only vs B skip).
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p176; mkdir -p $R
T5S=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5s)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
V="BONSAI_BIN=$T5S;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0;LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p176_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
}
for arm in A B C; do
  X="$V"; [ $arm != B ] && X="$V;GGML_CUDA_FA_CHUNK_SKIP=0"
  serve $arm "$X"
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 128000 --out $R/$arm.txt >> $R/run.txt 2>&1
done
python -c "
import hashlib, sys
h = {a: hashlib.sha256(open(sys.argv[1] + '/' + a + '.txt', 'rb').read()).hexdigest()[:16] for a in 'ABC'}
print('P176', h, 'EXACT' if h['A'] == h['B'] == h['C'] else ('NOT EXACT' if h['A'] == h['C'] else 'DRIFT (A != C)'))
" $R >> $R/run.txt
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
