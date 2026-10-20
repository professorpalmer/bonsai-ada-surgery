#!/usr/bin/env bash
# P213 (R6 groundwork for replay rollback on the RTX 2060, before a release; #201: "default-on waits for R6 on the RTX 2060"):
# bins = fork product-0069 (a6d4fc698) + patch 0070 (64b85111e, git am of patches/0070 from main), built here for 75-real;
# r6test/ = the 18f zip tree with main's start-server.ps1 (it knows BONSAI_RS_REPLAY) and these bins.
# Gates (declared before the run):
#  A identity, line pinned 80,640, BONSAI_SPARSE=0: replay off vs on, det_answer 4k / 32k / 128k: byte-equal (the 0070 claim).
#  B default sizing, off vs on: the launcher's VRAM line (expect ~+10k cells with on), cold 128k (det 128k prefill), decode at
#    128k (det 128k, 400 tokens), trace min free >= 60 MiB, 0 spill lines.
#  C soak, replay on, defaults, the 18f layer with the cache: 12 turns of the P164 session, restarts before 4 / 7 / 10; 0 CUDA
#    errors, 0 one-token answers, min free >= 60 MiB; answers vs P212 (cache-off, line 80,640-class) reported, not gated
#    (the VRAM line differs).
#  op tests on sm_75 first: GATED_DELTA_NET, SSM_CONV, FLASH_ATTN_EXT 0 FAIL (else stop). 0 CUDA errors everywhere; the launcher
#  scan: 0 control bytes.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p213; mkdir -p $R
for i in $(seq 1 180); do grep -q "0070 exit" receipts/build_ahead.log && break; sleep 10; done
grep -q "0070 exit 0" receipts/build_ahead.log || { echo "$(date +%T) bin-0070 build missing: stop" >> $R/run.txt; exit 1; }
rm -rf r6test/bin; cp -r /c/bonsai/bonsai-ada-surgery/bin-0070 r6test/bin
python -c "
import sys
b=open(sys.argv[1],'rb').read(); print('launcher control bytes:', sum(1 for c in b if c<32 and c not in (9,10,13)))
b=open(sys.argv[2],'rb').read(); print('llama.dll has LLAMA_RS_REPLAY:', b'LLAMA_RS_REPLAY' in b)
" "$(cygpath -w r6test/start-server.ps1)" "$(cygpath -w r6test/bin/llama.dll)" >> $R/run.txt
L=$(cygpath -w r6test/start-server.ps1); KEY=$(cygpath -w r6test/artifacts/api_key.txt)
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
for op in GATED_DELTA_NET SSM_CONV FLASH_ATTN_EXT; do echo "op $op: $(r6test/bin/test-backend-ops.exe test -o $op -b CUDA0 < /dev/null 2>&1 | grep -E 'tests passed|FAIL' | tr -d '' | tail -2 | tr '
' ' ')"; done >> $R/run.txt
grep -q "FAIL" $R/run.txt && { echo "$(date +%T) op test FAIL: stop" >> $R/run.txt; exit 0; }
serve() { # $1 tag, $2 vars
  powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
  schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
  powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag "p213_$1" -Launcher "$L" -Vars "$2" >/dev/null 2>&1
  for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
  O=$(ls -t logs/*p213_$1*.out.log | head -1); E="${O%.out.log}.err.log"
  grep -hE "^(8gb|kv +tiered|vram|spec|note)" "$O" | sed "s/^/$1: /" >> $R/run.txt
}
note() { echo "$(date +%T) $1 CUDA error lines: $(grep -ciE 'cuda error' "$E"); spill lines: $(grep -c '^spill' "$O")" >> $R/run.txt; }
memon() { ( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 5; done ) > $R/$1.mem.txt & MP=$!; }
memoff() { kill $MP; awk '{v=$2+0; if (NR==1||v<m) m=v} END{print "'$1' trace min free", m, "MiB"}' $R/$1.mem.txt >> $R/run.txt; }
# A identity, pinned line
for arm in Aoff Aon; do
  V="BONSAI_KV_VRAM_CELLS=80640;BONSAI_SPARSE=0"; [ $arm = Aon ] && V="$V;BONSAI_RS_REPLAY=1"
  serve $arm "$V"
  for d in 4000 32000 128000; do
    PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file "$KEY" --depth $d --out $R/${arm}_d$d.txt >> $R/run.txt 2>&1
  done
  note $arm
done
python -c "
import hashlib, sys
for d in ('4000', '32000', '128000'):
    a, b = [hashlib.sha256(open(sys.argv[1] + '/' + x + '_d' + d + '.txt', 'rb').read()).hexdigest()[:16] for x in ('Aoff', 'Aon')]
    print('A d' + d, 'off', a, 'on', b, 'PASS' if a == b else 'FAIL')
" $R >> $R/run.txt
# B default sizing
for arm in Boff Bon; do
  V=""; [ $arm = Bon ] && V="BONSAI_RS_REPLAY=1"
  serve $arm "$V"; memon $arm
  PYTHONUTF8=1 python det_answer.py --base http://127.0.0.1:8080 --key-file "$KEY" --depth 128000 --out $R/${arm}_d128000.txt >> $R/run.txt 2>&1
  memoff $arm; note $arm
done
# C soak, replay on
RA=$R/soak; mkdir -p $RA; rm -rf slots213; mkdir -p slots213
SW="C:/bonsai/8gb/slots213"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
unset BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN BONSAI_SLOT_CACHE_EVERY
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p211_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 150); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done; }
memon soak
for k in $(seq 1 12); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then
    if [ -n "$LP" ]; then idle; kill $LP 2>/dev/null; LP=""; fi
    serve soak_t$k "BONSAI_RS_REPLAY=1;BONSAI_SLOT_SAVE_PATH=$SW"; layer t$k
  fi
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
idle; [ -n "$LP" ] && kill $LP 2>/dev/null
memoff soak
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots213
python - "$(cygpath -w $RA/turns.jsonl)" "$(cygpath -w receipts/p212/turns.jsonl)" >> $R/run.txt <<'PY'
import json, sys
a = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
b = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[2], encoding='utf-8')}
same = sum(1 for r in a if (r['answer'] or '').strip() == (b[r['turn']]['answer'] or '').strip())
print('C soak turns', len(a), 'one-token', sum(1 for r in a if r.get('predicted_n') == 1), 'answers = P212 (report only):', same)
for r in a: print('  turn', r['turn'], 'wall', r['wall_s'], 'P212', b[r['turn']]['wall_s'])
PY
echo "CUDA error logs: $(grep -l 'CUDA error' logs/*p213_*.err.log 2>/dev/null | wc -l)" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
