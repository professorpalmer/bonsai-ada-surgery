#!/usr/bin/env bash
# P178 (T5 with run-based skip + dense layers): bin-t5r = fork t5-window-emu HEAD (T5 mask + dense=il:... second mask + the
# chunked prefill attention runs only kept 256-cell blocks, merged into runs of <= GGML_CUDA_FA_CHUNK cells; exact), 75-real.
# Recipe as P175: 1017 launcher copy, layer off, line pinned 80,640, BONSAI_SPARSE=0, default chunks (32,768).
# Gates (declared before the run):
#   R-0: env unset = product, in-block: det_answer 4k + 32k, zip then t5r: equal sha256 (dense runs = the fixed grid).
#   R-1: n24 at 245k, window 16384 / sink 1024 / tail 1024: cold time (P175 fixed-grid skip 991 s, dense ~1,452 s) and n24
#        (P175 22/24, P174b 23/24).
#   R-2: cold 128k read with the window (P175 S-3 fixed grid 484.1 s, dense ~532 s).
#   R-3: prose set, window 16k + dense=15:31:47:63 (4 of the 16 full-attention layers dense): vs dense 11/24, T5 16k 5/24.
#   R-4: prose set, window 32768 / sink 1024 / tail 1024, no dense layers: vs the same.
#   Report every cold time; 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p178; mkdir -p $R
for i in $(seq 1 120); do grep -q "t5r exit" receipts/build_ahead.log && break; sleep 10; done
grep -q "t5r exit 0" receipts/build_ahead.log || { echo "$(date +%T) bin-t5r build missing: stop" >> $R/run.txt; exit 1; }
ZIP=$(cygpath -w "$(cd "$(dirname "$(find release_1017/x -name llama-server.exe | head -1)")" && pwd)")
T5R=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
W16="LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p178_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p178_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$(date +%T) $1 up: $(grep -hE '^kv +tiered' "$O" | cut -c1-80)" >> $R/run.txt
}
cuda() { echo "$(date +%T) $1 CUDA error lines: $(grep -ciE 'cuda error|out of memory' "$E"); window: $(grep -h 'prefill window on' "$E" | sed 's/.*experimental): //' | head -1)" >> $R/run.txt; }
# R-0
for arm in zip t5r; do
  B=$T5R; [ $arm = zip ] && B=$ZIP
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
    a, b = h('zip_d' + d + '.txt'), h('t5r_d' + d + '.txt')
    print('R-0 d' + d, 'zip', a, 't5r', b, 'PASS' if a == b else 'FAIL')
" $R >> $R/run.txt
grep -q "R-0 .* FAIL" $R/run.txt && { echo "$(date +%T) R-0 failed: stop" >> $R/run.txt; exit 0; }
# R-1
serve n24 "BONSAI_BIN=$T5R;$B0;$W16"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag t5r_245000 --out $R/needle24.jsonl > $R/n24.txt 2>&1
tail -1 $R/n24.txt >> $R/run.txt; cuda n24
python -c "
import json, sys
a = [json.loads(l) for l in open(sys.argv[1]) if '\"vault\"' in l]
print('R-1 cold', a[0]['wall_s'] if a else None, 's; lost', [x['vault'] for x in a if not x['ok']])
" $R/n24.txt >> $R/run.txt
# R-2
serve r128 "BONSAI_BIN=$T5R;$B0;$W16"
PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 128000 --salt r2_128 >> $R/run.txt 2>&1
cuda r128
# R-3, R-4
for arm in d4 w32; do
  case $arm in
    d4)  WV="LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024,dense=15:31:47:63";;
    w32) WV="LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024";;
  esac
  serve prose_$arm "BONSAI_BIN=$T5R;$B0;$WV"
  PYTHONUTF8=1 python p170_drive.py --set prose --arm dense --key-file $KEY --out $R/prose_$arm.jsonl > $R/prose_$arm.txt 2>&1
  echo "$(date +%T) prose $arm ok $(grep -c '"ok": true' $R/prose_$arm.txt) of $(grep -c '"item"' $R/prose_$arm.txt); cold $(grep -m1 '"item"' $R/prose_$arm.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s" >> $R/run.txt
  cuda prose_$arm
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
