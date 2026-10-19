#!/usr/bin/env bash
# release-20261019b R1-R4, R6 on the zip (gates: bonsai-saa docs/research/release-20261019b, declared before the runs).
B=<checkout>; SP=$(dirname "$(realpath "$0")")
OLDSP=<scratchpad>
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261019b.zip; OLD=$B/artifacts/release/bonsai-bundle-win-x64-20261019a.zip
U=$TEMP/r-1019bz; LOG=$SP/release_1019b.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*r-1019bz*bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"; }
trap stopall EXIT
rm -rf "$U"; mkdir -p "$U"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $ZIP)" "$(cygpath -w $U)"
[ -d "$U/layer/runtime" ] || cp -r $B/layer/runtime "$U/layer/"
mkdir -p "$U/artifacts" && cp artifacts/api_key.txt "$U/artifacts/api_key.txt"
say "=== release-20261019b: zip sha256 $(sha256sum $ZIP | cut -c1-16), engine $("$U/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
say "R1 $(python -I -c "
import zipfile,re,sys
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
na=set(n for n in a.namelist() if not n.endswith('/')); nb=set(n for n in b.namelist() if not n.endswith('/'))
oa=set(n for n in na if not n.startswith('docs/')); ob=set(n for n in nb if not n.startswith('docs/'))
diff=sorted(n for n in oa&ob if a.read(n)!=b.read(n))
rt=[n for n in na if n.startswith('bin/') and ('cublas' in n or 'cudart' in n or 'nvJitLink' in n or 'nvvm' in n)]
bad=[n for n in na if n.endswith(('.ps1','.py','.md','.sh','.txt','.json','.jinja','.html')) and re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', a.read(n))]
print('outside docs: only-new', sorted(oa-ob), 'only-old', sorted(ob-oa), 'runtime identical', all(a.read(n)==b.read(n) for n in rt), 'changed', diff, '| docs files', len(na-oa), '| control-byte files', len(bad))" "$(cygpath -w $ZIP)" "$(cygpath -w $OLD)")"
start() { local NAME=$1; shift; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $U)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\r19b_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\r19b_$NAME.server.log'"
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($*): health=$ok; $(grep -E '^(kv |spec )' logs/r19b_$NAME.launcher.log | cut -c1-70 | tr '\n' '|') RS $(grep -h 'RS buffer size' logs/r19b_$NAME.server.log | head -1 | grep -o '[0-9.]* MiB'); replay $(grep -c 'replay rollback' logs/r19b_$NAME.server.log)"; [ $ok = 1 ]; }
KEYU="$U/artifacts/api_key.txt"
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $KEYU)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours and one fact about each."}],"max_tokens":60,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:200].replace(chr(10),' '))" 2>&1; }
S2=$TEMP/r19b_slots_r2; rm -rf $S2
for arm in "default|BONSAI_LAYER=0" "8gb|BONSAI_8GB=1 BONSAI_SLOT_SAVE_PATH=$(cygpath -w $S2)" "8gb_r0|BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_RS_REPLAY=0" "24gb|BONSAI_LAYER=0 BONSAI_TOTAL_MIB=24576"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}
  start $NAME $ENVS && { sleep 15; A=$(ask); say "R2 $NAME: answer: ${A:0:90}; CUDA errors $(grep -c 'CUDA error' logs/r19b_$NAME.server.log)"; }
done
# R3: the graph line past a pinned VRAM line
if start r3 BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_KV_VRAM_CELLS=32768; then
  PYTHONUTF8=1 python "$(cygpath -w $OLDSP/replay/r2.py)" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" 40000 "$(cygpath -m $SP)/r3.jsonl" r3 2>&1 | tail -1 | cut -c1-160 >> "$LOG"
  say "R3 graph-check warnings $(grep -c 'ggml_cuda_graph_check_compability' logs/r19b_r3.server.log) (at most 2); records $(grep -c . $SP/r3.jsonl); CUDA errors $(grep -c 'CUDA error' logs/r19b_r3.server.log)"
fi
idx() { python -I -c "
import json,sys
idx={}
for l in open(sys.argv[1]):
    e=json.loads(l)
    if e.get('drop'): idx.pop(e['sha'],None)
    else: idx[e['sha']]=e
print(len(idx), 'entries;', sum(1 for e in idx.values() if e.get('parent')), 'deltas')" "$1"; }
SG=$TEMP/r19b_slots_r4; rm -rf $SG; mkdir -p $SG
if start r4 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 BONSAI_SLOT_SAVE_PATH="$(cygpath -w $SG)"; then
  PYTHONUTF8=1 python "$(cygpath -w $OLDSP/saa/r5_turns.py)" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" "$(cygpath -w $SG)" 2>&1 | while read -r l; do say "R4 $l"; done
  PYTHONUTF8=1 python "$(cygpath -w $OLDSP/rel1018f/r4_interleave.py)" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" 2>&1 | while read -r l; do say "R4 $l"; done
  say "R4 index $(idx "$(cygpath -w $SG/lc-index.jsonl)"); CUDA errors $(grep -c 'CUDA error' logs/r19b_r4.server.log)"
fi
stopall; rm -rf $S2 $SG
# R6: 12 GB default speed, a fresh server per depth
for d in 4000 32000; do bash bench/depth_table.sh "$(cygpath -w $U)" rel1019b-$d $d > /dev/null 2>&1; say "R6 $d: $(grep 'mean decode' docs/receipts/depth_table_rel1019b-$d.log | tail -1)"; done
say "=== release-20261019b done"
