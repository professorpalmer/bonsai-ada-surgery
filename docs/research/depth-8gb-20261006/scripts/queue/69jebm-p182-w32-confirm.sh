#!/usr/bin/env bash
# P182 (T5 candidate = window 32k / sink 1k / tail 1k, run skip, bin-t5r3; P178 R-4 prose 9/24 at 1.77x): confirm on the other
# sets, and one more layer screen. Recipe as P181.
#   n24: needle n24 at 245k, window 32k (dense 23/24; T5 16k 21-23).
#   code: P170 code set, window 32k (dense 20/24; T5 16k 20).
#   f4: prose, window 16k + dense=3:7:11:15 (the first 4 full-attention layers; P181 e4 9/24, l4 5/24).
# Report ok vs dense item by item, cold times; 0 CUDA errors.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p182; mkdir -p $R
T=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r3)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_BIN=$T;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p182_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p182_$1*.out.log | head -1); E="${O%.out.log}.err.log"
}
note() { echo "$(date +%T) $1; CUDA error lines $(grep -ciE 'cuda error' "$E"); $(grep -h 'prefill window on' "$E" | sed 's/.*experimental): //')" >> $R/run.txt; }
serve n24 "$B0;LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 245000 --n 24 --tag t5_w32_245000 --out $R/needle24.jsonl > $R/n24.txt 2>&1
note "n24 $(tail -1 $R/n24.txt); cold $(head -1 $R/n24.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s; lost $(python -c "import json,sys; print([json.loads(l)['vault'] for l in open(sys.argv[1]) if '\"vault\"' in l and not json.loads(l)['ok']])" $R/n24.txt)"
for arm in code f4; do
  case $arm in
    code) S=code;  WV="window=32768,sink=1024,tail=1024";;
    f4)   S=prose; WV="window=16384,sink=1024,tail=1024,dense=3:7:11:15";;
  esac
  serve $arm "$B0;LLAMA_PREFILL_WINDOW=$WV"
  PYTHONUTF8=1 python p170_drive.py --set $S --arm dense --key-file $KEY --out $R/${arm}.jsonl > $R/${arm}.txt 2>&1
  note "$arm ($S) ok $(grep -c '"ok": true' $R/${arm}.txt) of $(grep -c '"item"' $R/${arm}.txt); cold $(grep -m1 '"item"' $R/${arm}.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s"
done
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
