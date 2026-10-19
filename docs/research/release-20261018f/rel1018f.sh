#!/usr/bin/env bash
# release-20261018f R1-R4 on the staged zip (gates in docs/research/release-20261018f, declared before the runs).
B=/c/Users/pwall/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")"); RD=/c/Users/pwall/Projects/bonsai-rel1018/docs/research/release-20261018f; mkdir -p $RD
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261018f.zip; OLD=$B/artifacts/release/bonsai-bundle-win-x64-20261018e.zip
U=$TEMP/r-1018fz; LOG=$RD/release_1018f.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*r-1018fz*bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"; }
trap stopall EXIT
rm -rf "$U"; mkdir -p "$U"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $ZIP)" "$(cygpath -w $U)"
[ -d "$U/layer/runtime" ] || cp -r $B/layer/runtime "$U/layer/"
say "=== release-20261018f R1-R4: zip sha256 $(sha256sum $ZIP | cut -c1-16), engine $("$U/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
say "R1 $(python -I -c "
import zipfile,re,sys
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
na=set(n for n in a.namelist() if not n.endswith('/')); nb=set(n for n in b.namelist() if not n.endswith('/'))
binsame=all(a.read(n)==b.read(n) for n in na if n.startswith('bin/'))
diff=sorted(n for n in na&nb if a.read(n)!=b.read(n))
bad=[n for n in na if n.endswith(('.ps1','.py','.md','.sh','.txt','.json','.jinja')) and re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', a.read(n))]
print('entries', len(na), 'only-new', sorted(na-nb), 'only-old', sorted(nb-na), 'bin identical', binsame, 'changed', diff, 'control-byte files', len(bad))" "$(cygpath -w $ZIP)" "$(cygpath -w $OLD)")"
start() { local NAME=$1; shift; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $U)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\r18f_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\r18f_$NAME.server.log'"
  local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "server $NAME ($*): health=$ok; $(grep -E '^(window|layer)' logs/r18f_$NAME.launcher.log | head -2 | cut -c1-60 | tr '\n' '|')"; [ $ok = 1 ]; }
KEYU="$U/artifacts/api_key.txt"
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $KEYU)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours."}],"max_tokens":24,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:50].replace(chr(10),' '))" 2>&1; }
S2=$TEMP/r18f_slots_r2; rm -rf $S2
for arm in "default|BONSAI_LAYER=0" "8gb|BONSAI_8GB=1 BONSAI_SLOT_SAVE_PATH=$(cygpath -w $S2)" "24gb|BONSAI_LAYER=0 BONSAI_TOTAL_MIB=24576"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}
  start $NAME $ENVS && { sleep 15; say "R2 $NAME: answer: $(ask); CUDA errors $(grep -c 'CUDA error' logs/r18f_$NAME.server.log)"; }
done
idx() { python -I -c "
import json,sys
idx={}
for l in open(sys.argv[1]):
    e=json.loads(l)
    if e.get('drop'): idx.pop(e['sha'],None)
    else: idx[e['sha']]=e
print(len(idx), 'entries;', sum(1 for e in idx.values() if e.get('parent')), 'deltas;', sorted((e['n'], e.get('depth')) for e in idx.values()))" "$1"; }
SG=$TEMP/r18f_slots_r3; rm -rf $SG; mkdir -p $SG
if start r3 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 BONSAI_SLOT_SAVE_PATH="$(cygpath -w $SG)"; then
  say "R3 status $(curl -s -m 5 http://127.0.0.1:8080/layer/slot-cache)"
  PYTHONUTF8=1 python "$SP/../saa/r5_turns.py" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" "$(cygpath -w $SG)" 2>&1 | while read -r l; do say "R3 $l"; done
  say "R3 index $(idx "$(cygpath -w $SG/lc-index.jsonl)"); CUDA errors $(grep -c 'CUDA error' logs/r18f_r3.server.log)"
fi
SG=$TEMP/r18f_slots_r4; rm -rf $SG; mkdir -p $SG
if start r4 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 BONSAI_SLOT_SAVE_PATH="$(cygpath -w $SG)"; then
  PYTHONUTF8=1 python "$SP/r4_interleave.py" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" 2>&1 | while read -r l; do say "R4 $l"; done
  say "R4 index $(idx "$(cygpath -w $SG/lc-index.jsonl)"); CUDA errors $(grep -c 'CUDA error' logs/r18f_r4.server.log)"
fi
stopall
say "=== release-20261018f R1-R4 done"
