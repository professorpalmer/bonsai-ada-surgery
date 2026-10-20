#!/usr/bin/env bash
# P220 (formal R6 for bundle-20261019b on the RTX 2060, asked in #138 6278575184 / 6279028757): zip 616,377,333 B, SHA-256
# d5a53c2b...8328c561 = the GitHub asset digest; engine 810d93e5aa (0070 + 0071); the 8 GB preset defaults to replay on + draft 2
# / tail 2. The zip's own launcher, defaults.
# Gates (declared before the run): (1) the launcher has 0 control bytes and prints the replay line and draft 2 / tail 2;
# (2) quick_tps sweep, a fresh server per depth (the P150 / P163 method), at 4k / 64k / 128k / 160k / 245k: report against the
# old 1 / 1 numbers on the cards (53.4 / 41.2 / 22.3 / 16.7 / 9.8 tok/s); no depth slower by more than 3 %; (3) soak ~30 min:
# P164's 30-turn session through the zip's layer (p220_layer.py, cache on, GROW 4096), restarts before every 3rd turn: 30/30
# answered, 0 one-token, min free >= 60 MiB; (4) 0 CUDA errors everywhere.
export QTPS_TIMEOUT=10800
cd /c/bonsai/8gb; R=receipts/p220; mkdir -p $R
touch $R/run.txt.start
ZR=release_1019b/x
[ -e "$ZR/models" ] || powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$ZR")/models' -Target 'C:/bonsai/bonsai-ada-surgery/models'" < /dev/null >> $R/zip.txt 2>&1
mkdir -p "$ZR/artifacts"; cp -n C:/bonsai/bonsai-ada-surgery/artifacts/api_key.txt "$ZR/artifacts/api_key.txt"
L=$(cygpath -w $ZR/start-server.ps1); KEY=$(cygpath -w $ZR/artifacts/api_key.txt)
python -c "
import sys
b=open(sys.argv[1],'rb').read(); print('G1 launcher control bytes:', sum(1 for c in b if c<32 and c not in (9,10,13)))
" "$L" >> $R/run.txt
for d in 4000 64000 128000 160000 245000; do
  bash run_arm.sh $R sweep_$d "" "$L" "$d" > /dev/null 2>&1
  grep -E "mean decode|depth" $R/sweep_$d.txt | sed "s/^/d$d: /" >> $R/run.txt
  O=$(ls -t logs/*sweep_$d*.out.log | head -1); E="${O%.out.log}.err.log"
  [ $d = 4000 ] && grep -hE "^(8gb|window|kv +tiered|vram|spec|recur|replay|note)" "$O" | sed 's/^/launcher: /' >> $R/run.txt
  echo "d$d CUDA error lines: $(grep -ciE 'cuda error' "$E"); min free at end: $(grep 'min free' $R/sweep_$d.txt)" >> $R/run.txt
done
RA=$R/soak; mkdir -p $RA; rm -rf slots220; mkdir -p slots220
SW="C:/bonsai/8gb/slots220"
export BONSAI_SLOT_SAVE_PATH="$SW" BONSAI_SLOT_CACHE_GROW=4096
unset BONSAI_SLOT_CACHE_AFTER BONSAI_SLOT_CACHE_CHAIN BONSAI_SLOT_CACHE_EVERY
LP=""
layer() { [ -n "$LP" ] && kill $LP 2>/dev/null; sleep 1
  PYTHONUTF8=1 python p220_layer.py --port 8081 --upstream http://127.0.0.1:8080 --cache > $RA/layer_$1.log 2>&1 & LP=$!
  for i in $(seq 1 30); do curl -s -m 2 localhost:8081/health | grep -q ok && break; sleep 1; done; }
idle() { for i in $(seq 1 150); do curl -s -m 2 localhost:8081/layer/slot-cache | grep -q '"busy": *false' && return 0; sleep 2; done; }
( while :; do echo "$(date +%T) $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"; sleep 10; done ) > $RA/mem.txt & MP=$!
for k in $(seq 1 30); do
  if [ $k = 1 ] || [ $(( (k - 1) % 3 )) = 0 ]; then
    if [ -n "$LP" ]; then idle; kill $LP 2>/dev/null; LP=""; fi
    powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
    schtasks //run //tn BonsaiAB_P3 >/dev/null; sleep 4; schtasks //run //tn BonsaiAB_P5 >/dev/null; sleep 6
    powershell -NoProfile -ExecutionPolicy Bypass -File serve.ps1 -Tag p220_soak_t$k -Launcher "$L" -Vars "BONSAI_SLOT_SAVE_PATH=$SW" >/dev/null 2>&1
    for i in $(seq 1 120); do curl -s localhost:8080/health | grep -q ok && break; sleep 5; done
    layer t$k
  fi
  PYTHONUTF8=1 python p155_turn.py --key-file "$KEY" --depth 131072 --turn $k --arm S --state $RA/state.json --out $RA/turns.jsonl 2>&1 | tail -1 >> $RA/run.txt
done
idle; [ -n "$LP" ] && kill $LP 2>/dev/null; kill $MP
powershell -NoProfile -ExecutionPolicy Bypass -File stop.ps1 >/dev/null 2>&1
rm -rf slots220
python - "$(cygpath -w $RA/turns.jsonl)" "$(cygpath -w receipts/p200/g4096/turns.jsonl)" >> $R/run.txt <<'PY'
import json, statistics, sys
a = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
b = {json.loads(l)['turn']: json.loads(l) for l in open(sys.argv[2], encoding='utf-8')}
rst = [r['wall_s'] for r in a if r['turn'] > 1 and (r['turn'] - 1) % 3 == 0]
nrm = [r['wall_s'] for r in a if r['turn'] > 1 and (r['turn'] - 1) % 3 != 0]
print('soak turns', len(a), 'empty', sum(1 for r in a if not (r['answer'] or '').strip()), 'one-token', sum(1 for r in a if r.get('predicted_n') == 1))
print('soak total', round(sum(r['wall_s'] for r in a)), 's; restart mean', round(statistics.mean(rst), 1), 'normal mean', round(statistics.mean(nrm), 1),
      '| P200 GROW 4096 (bundle 18, 1 / 1): total', round(sum(b[t]['wall_s'] for t in b)), 'restart', round(statistics.mean([b[t]['wall_s'] for t in b if t > 1 and (t - 1) % 3 == 0]), 1),
      'normal', round(statistics.mean([b[t]['wall_s'] for t in b if t > 1 and (t - 1) % 3 != 0]), 1))
PY
awk '{v=$2+0; if (NR==1||v<m) m=v} END{print "soak trace min free", m, "MiB"}' $RA/mem.txt >> $R/run.txt
echo "CUDA error logs (this run): $(find logs -name '*.err.log' -newer $R/run.txt.start -print0 | xargs -0 grep -l 'CUDA error' 2>/dev/null | wc -l) of $(find logs -name '*.err.log' -newer $R/run.txt.start | wc -l) logs" >> $R/run.txt
echo "$(date +%T) done" >> $R/run.txt
