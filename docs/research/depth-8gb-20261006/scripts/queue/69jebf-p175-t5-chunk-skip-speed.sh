#!/usr/bin/env bash
# P175 (T5 speed: the exact chunk skip): bin-t5s = fork t5-window-emu d048068ca (T5 mask rule + the chunked prefill attention
# skips a K/V chunk that no row of the packed mask keeps; exact, on by default, GGML_CUDA_FA_CHUNK_SKIP=0 off), 75-real.
# Recipe as P174b: 1017 launcher copy, layer off, line pinned 80,640, BONSAI_SPARSE=0, fresh server per arm.
# Gates (declared before the run):
#   S-0: env unset = product, in-block: det_answer 4k + 32k, zip then t5s: equal sha256 (the skip never fires on a dense mask).
#   S-1: n24 at 245k, window=16384,sink=1024,tail=1024, default chunks (GGML_CUDA_FA_CHUNK=32768 from the launcher): the 24
#        answers equal P174b's (23/24; the skip is exact); report the cold time vs P174b 1,452.2 s (mask only = dense speed).
#   S-2: the same with GGML_CUDA_FA_CHUNK=8192 (finer chunks: fewer kept cells): report the cold time and n24 (chunk merges
#        change rounding, so answers may differ from S-1).
#   S-3: a cold 128k read (p168_read.py) with the window, the faster chunk size of S-1 / S-2: vs dense ~532 s (P168).
#   0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p175; mkdir -p $R
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
T5S=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5s)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
W="LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p175_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p175_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$(date +%T) $1 up: $(grep -hE '^kv +tiered' "$O" | cut -c1-80)" >> $R/run.txt
}
cuda() { echo "$(date +%T) $1 CUDA error lines: $(grep -ciE 'cuda error|out of memory' "$E"); window lines: $(grep -c 'prefill window on' "$E"); chunk line: $(grep -h 'GGML_CUDA_FA_CHUNK: chunks' "$E" | sed 's/.*chunks of/chunks of/' | head -1)" >> $R/run.txt; }
# S-0
for arm in zip t5s; do
  B=$T5S; [ $arm = zip ] && B=$ZIP
  for d in 4000 32000; do
    serve ${arm}_d$d "BONSAI_BIN=$B;$B0"
    PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth $d --out $R/${arm}_d$d.txt >> $R/run.txt 2>&1
    cuda ${arm}_d$d
  done
done
python -c "
import hashlib, sys
h = lambda f: hashlib.sha256(open(sys.argv[1] + '/' + f, 'rb').read()).hexdigest()[:16]
for d in ('4000', '32000'):
    a, b = h('zip_d' + d + '.txt'), h('t5s_d' + d + '.txt')
    print('S-0 d' + d, 'zip', a, 't5s', b, 'PASS' if a == b else 'FAIL')
" $R >> $R/run.txt
grep -q "S-0 .* FAIL" $R/run.txt && { echo "$(date +%T) S-0 failed: stop" >> $R/run.txt; exit 0; }
# S-1
serve n24_c32k "BONSAI_BIN=$T5S;$B0;$W"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag t5s_c32k_245000 --out $R/needle24.jsonl > $R/n24_c32k.txt 2>&1
tail -1 $R/n24_c32k.txt >> $R/run.txt; cuda n24_c32k
python -c "
import json, sys
a = [json.loads(l) for l in open(sys.argv[1]) if '\"vault\"' in l]
b = [json.loads(l) for l in open(sys.argv[2]) if '\"vault\"' in l]
same = sum(x['answer'] == y['answer'] for x, y in zip(a, b))
print('S-1 answers equal to P174b:', same, 'of', len(a), '; cold', a[0]['wall_s'], 's vs P174b', b[0]['wall_s'], 's')
" $R/n24_c32k.txt receipts/p174b/n24_w16k.txt >> $R/run.txt
# S-2
serve n24_c8k "BONSAI_BIN=$T5S;$B0;$W;GGML_CUDA_FA_CHUNK=8192"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag t5s_c8k_245000 --out $R/needle24.jsonl > $R/n24_c8k.txt 2>&1
tail -1 $R/n24_c8k.txt >> $R/run.txt; cuda n24_c8k
python -c "
import json, sys
a = [json.loads(l) for l in open(sys.argv[1]) if '\"vault\"' in l]
print('S-2 cold', a[0]['wall_s'], 's')
" $R/n24_c8k.txt >> $R/run.txt
# S-3: the faster chunk size
CS=$(python -c "
import json, sys
a = json.loads(open(sys.argv[1]).readline())['wall_s']; b = json.loads(open(sys.argv[2]).readline())['wall_s']
print('8192' if b < a else '32768')
" $R/n24_c32k.txt $R/n24_c8k.txt)
serve r128 "BONSAI_BIN=$T5S;$B0;$W;GGML_CUDA_FA_CHUNK=$CS"
echo "$(date +%T) S-3 chunk size $CS" >> $R/run.txt
PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 128000 --salt s3_128 >> $R/run.txt 2>&1
cuda r128
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
