#!/usr/bin/env bash
# P174 (T5 prefill window, quality screen; research nugget: Star Attention / SWAA "full attention for the query"): bin-t5 =
# fork t5-window-emu c675d5c78 (= the bundle-20261017 engine 96f6e49cd + a mask rule), built for 75-real. LLAMA_PREFILL_WINDOW=
# "window=W,sink=S,tail=T": while a prompt is read, ubatches that end before n_prompt - T mask cells S <= pos < p - W in the
# 16 full-attention layers; the tail (the question) and decode stay dense. Mask only: the same speed as dense (this screens
# quality before anyone builds the fast path; the cost model says W 16k + S 1k cuts a 245k read 1,489 -> ~650 s).
# 1017 launcher copy, layer off, line pinned 80,640, BONSAI_SPARSE=0 (dense decode, so only the prefill rule differs).
# Gates (declared before the run):
#   T5-0: env unset = product: det_answer sha256 at 4k and 32k equal to P169's zip hashes (d72631aab936fc4e / d77df25fc3f18819).
#   C0 (engagement control): det_answer at 32k with window=1024,sink=64,tail=0 must DIFFER from the dense hash; else stop.
#   C1 (report only): 64k needle n8, window=16384,sink=1024,tail=0: what the DeltaNet layers carry without dense question rows.
#   T5-1: needle n24 at 245k, window=16384,sink=1024,tail=1024: report vs the 2060 dense P148 23/24 (miss vault 14).
#   T5-2: P170 code set and prose set, the same window: report vs P170 dense 20/24 and 11/24.
#   Screen pass (for a fast-path build): T5-1 >= 22/24 and T5-2 within 1 item of dense on each set. 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p174; mkdir -p $R
T5=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
BASEV="BONSAI_BIN=$T5;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p174_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p174_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  echo "$(date +%T) $1 up: $(grep -hE '^kv +tiered' "$O" | cut -c1-80)" >> $R/run.txt
}
cuda() { echo "$(date +%T) $1 CUDA error lines: $(grep -ciE 'cuda error|out of memory' "$E"); window lines: $(grep -c 'prefill window on' "$E")" >> $R/run.txt; }
# T5-0
for d in 4000 32000; do
  serve off_d$d "$BASEV"
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth $d --out $R/off_d$d.txt >> $R/run.txt 2>&1
  cuda off_d$d
done
python -c "
import hashlib, sys
want = {'4000': 'd72631aab936fc4e', '32000': 'd77df25fc3f18819'}
ok = True
for d, w in want.items():
    h = hashlib.sha256(open(sys.argv[1] + '/off_d' + d + '.txt', 'rb').read()).hexdigest()[:16]
    print('T5-0 d' + d, h, 'want', w, 'PASS' if h == w else 'FAIL'); ok &= h == w
" $R >> $R/run.txt
grep -q "T5-0 .* FAIL" $R/run.txt && { echo "$(date +%T) T5-0 failed: stop" >> $R/run.txt; exit 0; }
# C0 engagement control: a tiny window on everything at 32k must change the answer bytes
serve c0 "$BASEV;LLAMA_PREFILL_WINDOW=window=1024,sink=64,tail=0"
PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file $KEY --depth 32000 --out $R/c0_d32000.txt >> $R/run.txt 2>&1
cuda c0
python -c "
import hashlib, sys
h = hashlib.sha256(open(sys.argv[1] + '/c0_d32000.txt', 'rb').read()).hexdigest()[:16]
print('C0 window 1024 tail 0 at 32k:', h, 'dense d77df25fc3f18819', 'ENGAGED' if h != 'd77df25fc3f18819' else 'NOT ENGAGED')
" $R >> $R/run.txt
grep -q "NOT ENGAGED" $R/run.txt && { echo "$(date +%T) C0: the mask does not engage: stop" >> $R/run.txt; exit 0; }
# C1 (report only): 64k needle n8, window 16k with the question windowed too: how much do the DeltaNet layers carry?
serve c1 "$BASEV;LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=0"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 64000 --n 8 --tag c1_w16k_tail0 --out $R/c1.jsonl > $R/c1.txt 2>&1
tail -1 $R/c1.txt >> $R/run.txt; cuda c1
# T5-1
W="LLAMA_PREFILL_WINDOW=window=16384,sink=1024,tail=1024"
serve n24_w16k "$BASEV;$W"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag t5_w16k_245000 --out $R/needle24.jsonl > $R/n24_w16k.txt 2>&1
tail -1 $R/n24_w16k.txt >> $R/run.txt; cuda n24_w16k
# T5-2
for s in code prose; do
  serve ${s}_w16k "$BASEV;$W"
  PYTHONUTF8=1 python p170_drive.py --set $s --arm dense --key-file $KEY --out $R/$s.jsonl > $R/${s}_w16k.txt 2>&1
  echo "$(date +%T) $s w16k ok $(grep -c '"ok": true' $R/${s}_w16k.txt) of $(grep -c '"item"' $R/${s}_w16k.txt)" >> $R/run.txt; cuda ${s}_w16k
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
