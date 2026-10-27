#!/usr/bin/env bash
# release-20261026 R1, R2, R4 on the zip (gates: docs/research/release-20261026, declared before the runs).
B=<projects>/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
OLDSP=<scratchpad>
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261026.zip; OLD=$B/artifacts/release/bonsai-bundle-win-x64-20261025.zip
U=$TEMP/r-1026z; LOG=$SP/release_1026.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*r-1026z*bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"; }
trap stopall EXIT
rm -rf "$U"; mkdir -p "$U"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $ZIP)" "$(cygpath -w $U)"
[ -d "$U/layer/runtime" ] || cp -r $B/layer/runtime "$U/layer/"
mkdir -p "$U/artifacts" && cp artifacts/api_key.txt "$U/artifacts/api_key.txt"
say "=== release-20261026: zip sha256 $(sha256sum $ZIP | cut -c1-16), engine $("$U/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
say "R1 $(python -I -c "
import zipfile,re,sys
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
na=set(n for n in a.namelist() if not n.endswith('/')); nb=set(n for n in b.namelist() if not n.endswith('/'))
oa=set(n for n in na if not n.startswith('docs/')); ob=set(n for n in nb if not n.startswith('docs/'))
print('outside docs: only-new', sorted(oa-ob), 'only-old', sorted(ob-oa), 'bin changed', sorted(n for n in oa if n.startswith('bin/') and a.read(n)!=b.read(n)),
      'changed', sorted(n for n in oa&ob if a.read(n)!=b.read(n)), '| docs new', sorted((na-oa)-(nb-ob)),
      '| control-byte files', len([n for n in na if n.endswith(('.ps1','.py','.md','.sh','.txt','.json','.jinja','.html')) and re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', a.read(n))]))" "$(cygpath -w $ZIP)" "$(cygpath -w $OLD)")"
start() { local NAME=$1; shift; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $U)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\r26_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\r26_$NAME.server.log'"
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($*): health=$ok; $(grep -E '^(spec |layer )|layer log:' logs/r26_$NAME.launcher.log | cut -c1-70 | tr '\n' '|') replay: $(grep -h -o 'pending inputs of [0-9]* tokens' logs/r26_$NAME.server.log | head -1); layer.log: $([ -f "$U/logs/layer.log" ] && echo exists || echo MISSING)"; [ $ok = 1 ]; }
KEYU="$U/artifacts/api_key.txt"
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $KEYU)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours and one fact about each."}],"max_tokens":60,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:200].replace(chr(10),' '))" 2>&1; }
for arm in "default|BONSAI_LAYER=0 LLAMA_ARG_LOG_VERBOSITY=4" "8gb|BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 LLAMA_ARG_LOG_VERBOSITY=4" "8gb_r0|BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_RS_REPLAY=0 BONSAI_KV_VRAM_CELLS=90112 LLAMA_ARG_LOG_VERBOSITY=4" "24gb|BONSAI_LAYER=0 BONSAI_TOTAL_MIB=24576 LLAMA_ARG_LOG_VERBOSITY=4"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}
  start $NAME $ENVS && { sleep 10; A=$(ask); say "R2 $NAME: answer: ${A:0:80}; CUDA errors $(grep -c 'CUDA error' logs/r26_$NAME.server.log)"; }
done
idx() { python -I -c "
import json,sys
idx={}
for l in open(sys.argv[1]):
    e=json.loads(l)
    if e.get('drop'): idx.pop(e['sha'],None)
    else: idx[e['sha']]=e
print(len(idx), 'entries;', sum(1 for e in idx.values() if e.get('parent')), 'deltas')" "$1"; }
SG=$TEMP/r26_slots_r4; rm -rf $SG; mkdir -p $SG
if start r4 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 BONSAI_SLOT_SAVE_PATH="$(cygpath -w $SG)"; then
  PYTHONUTF8=1 python "$(cygpath -w $OLDSP/saa/r5_turns.py)" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" "$(cygpath -w $SG)" 2>&1 | while read -r l; do say "R4 $l"; done
  PYTHONUTF8=1 python "$(cygpath -w $OLDSP/rel1018f/r4_interleave.py)" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" 2>&1 | while read -r l; do say "R4 $l"; done
  say "R4 index $(idx "$(cygpath -w $SG/lc-index.jsonl)"); CUDA errors $(grep -c 'CUDA error' logs/r26_r4.server.log)"
fi
stopall; rm -rf $SG
say "=== release-20261026 done"
