#!/usr/bin/env bash
# P183 (how big is run-to-run noise, and the 128k numbers for window 32k): bin-t5r3, recipe as P182.
#   dprose: the prose set DENSE again (P170 11/24; the rig drift may move items) - the noise floor for the T5 comparisons.
#   wprose: the prose set window 32k again (P178 R-4 9/24).
#   r128: cold 128k read, window 32k (dense ~532 s; window 16k 371 s).
#   n128: needle n24 at 128k, window 32k.
export QTPS_TIMEOUT=7200
cd /c/bonsai/8gb; R=receipts/p183; mkdir -p $R
T=$(cygpath -w /c/bonsai/bonsai-ada-surgery/bin-t5r3)
L='C:/bonsai/bonsai-ada-surgery/start-server-1017test.ps1'; KEY=C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt
B0="BONSAI_BIN=$T;BONSAI_LAYER=0;BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"
W="LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024"
serve() {
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p183_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p183_$1*.out.log | head -1); E="${O%.out.log}.err.log"
}
note() { echo "$(date +%T) $1; CUDA error lines $(grep -ciE 'cuda error' "$E")" >> $R/run.txt; }
for arm in dprose wprose; do
  V="$B0"; [ $arm = wprose ] && V="$B0;$W"
  serve $arm "$V"
  PYTHONUTF8=1 python p170_drive.py --set prose --arm dense --key-file $KEY --out $R/$arm.jsonl > $R/$arm.txt 2>&1
  note "$arm ok $(grep -c '"ok": true' $R/$arm.txt) of $(grep -c '"item"' $R/$arm.txt); cold $(grep -m1 '"item"' $R/$arm.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s"
done
serve r128 "$B0;$W"
PYTHONUTF8=1 python p168_read.py --key-file $KEY --depth 128000 --salt p183_128 >> $R/run.txt 2>&1
note "r128 done"
serve n128 "$B0;$W"
PYTHONUTF8=1 python benchx/needle_depth.py --key-file $KEY --depth 128000 --n 24 --tag t5_w32_128000 --out $R/needle24.jsonl > $R/n128.txt 2>&1
note "n128 $(tail -1 $R/n128.txt); cold $(head -1 $R/n128.txt | python -c 'import json,sys; print(json.loads(sys.stdin.read())["wall_s"])') s"
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
echo "$(date +%T) done" >> $R/run.txt
