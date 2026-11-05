#!/usr/bin/env bash
# release-20261105 R1-R6 on the zips (gates: docs/research/release-20261105/README.md, declared before the runs).
#   bash rel1105.sh <serve checkout with models/ and artifacts/release/> [steps, default "r1 r2 r4 r3 r5 r6"]
B=${1:?serve checkout}; STEPS=${2:-r1 r2 r4 r3 r5 r6}
SP=$(dirname "$(realpath "$0")"); RD=$(dirname "$SP"); BENCH=$(realpath "$RD/../../../bench")
cd "$B" || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261105.zip; OLDZ=$B/artifacts/release/bonsai-bundle-win-x64-20261026.zip
NEWR=$TEMP/r-1105z; OLDR=$TEMP/r-1026a; L=$(cygpath -u "$TEMP")/r1105-logs; rm -rf "$L"   # POSIX path: in a glob, the backslashes of $TEMP are escapes; mkdir -p "$L" "$RD/data"
LOG=$RD/data/release_1105.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $BENCH/stop_serve.ps1)" >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*r-1105z*bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"; }
trap stopall EXIT
unz() { rm -rf "$2"; mkdir -p "$2"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $1)" "$(cygpath -w $2)"
  [ -d "$2/layer/runtime" ] || cp -r $B/layer/runtime "$2/layer/"; mkdir -p "$2/artifacts" && cp artifacts/api_key.txt "$2/artifacts/api_key.txt"; }
unz $ZIP $NEWR; unz $OLDZ $OLDR   # always fresh: no folder of an earlier run
KEY="$(cygpath -w $NEWR/artifacts/api_key.txt)"
# start NAME ROOT ENV...: fresh server from ROOT's own launcher; health; owner check (llama-server listens on 8080
# with the layer off, on 18080 behind the layer)
start() { local NAME=$1 ROOT=$2; shift 2; stopall; sleep 4
  local OP=18080; case " $* " in *" BONSAI_LAYER=0 "*) OP=8080 ;; esac
  env BONSAI_MODEL="$MODEL" "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $ROOT)\start-server.ps1' -RedirectStandardOutput '$(cygpath -w $L)\\$NAME.launcher.log' -RedirectStandardError '$(cygpath -w $L)\\$NAME.server.log'" </dev/null >/dev/null 2>&1
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $BENCH/serve_owner.ps1)" -Root "$(cygpath -w $ROOT)" -Port $OP >/dev/null || ok=0
  say "server $NAME ($(basename $ROOT) $*): health=$ok; $(grep -E '^(spec |layer |kv )|layer log:' $L/$NAME.launcher.log | tr -d '\r' | cut -c1-90 | tr '\n' '|')"; [ $ok = 1 ]; }
cuda() { grep -c 'CUDA error' $L/$1.server.log; }
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $NEWR/artifacts/api_key.txt)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours and one fact about each."}],"max_tokens":60,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:200].replace(chr(10),' '))" 2>&1; }

for STEP in $STEPS; do case $STEP in
r1)
  say "=== release-20261105: zip sha256 $(sha256sum $ZIP | cut -c1-16), engine $("$NEWR/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*' | head -1); 1026 root $("$OLDR/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*' | head -1)"
  say "R1 $(python -I -c "
import zipfile,re,sys
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
na=set(n for n in a.namelist() if not n.endswith('/')); nb=set(n for n in b.namelist() if not n.endswith('/'))
oa=set(n for n in na if not n.startswith('docs/')); ob=set(n for n in nb if not n.startswith('docs/'))
print('outside docs: only-new', sorted(oa-ob), 'only-old', sorted(ob-oa), 'changed', sorted(n for n in oa&ob if a.read(n)!=b.read(n)),
      '| docs changed', sorted(n for n in (na-oa)&(nb-ob) if a.read(n)!=b.read(n)), 'docs new', sorted((na-oa)-(nb-ob)),
      '| control-byte files', len([n for n in na if n.endswith(('.ps1','.py','.md','.sh','.txt','.json','.jinja','.html')) and re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', a.read(n))]))" "$(cygpath -w $ZIP)" "$(cygpath -w $OLDZ)")"
  say "R1 unzipped bin/ = zip entries: $(python -I -c "
import zipfile,hashlib,os,sys
z=zipfile.ZipFile(sys.argv[1]); bad=[n for n in z.namelist() if n.startswith('bin/') and not n.endswith('/') and hashlib.sha256(z.read(n)).digest()!=hashlib.sha256(open(os.path.join(sys.argv[2],*n.split('/')),'rb').read()).digest()]
print('all equal' if not bad else 'DIFFER '+' '.join(bad))" "$(cygpath -w $ZIP)" "$(cygpath -w $NEWR)")" ;;
r2)
  for arm in "default|BONSAI_LAYER=0 LLAMA_ARG_LOG_VERBOSITY=4" "8gb|BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 LLAMA_ARG_LOG_VERBOSITY=4" "8gb_r0|BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_RS_REPLAY=0 BONSAI_KV_VRAM_CELLS=90112 LLAMA_ARG_LOG_VERBOSITY=4" "24gb|BONSAI_LAYER=0 BONSAI_TOTAL_MIB=24576 LLAMA_ARG_LOG_VERBOSITY=4"; do
    NAME=r2_${arm%%|*}; ENVS=${arm#*|}
    start $NAME $NEWR $ENVS && { sleep 10; A=$(ask); say "R2 $NAME: answer: ${A:0:80}; CUDA errors $(cuda $NAME); replay: $(grep -h -o 'pending inputs of [0-9]* tokens' $L/$NAME.server.log | head -1)"; } || say "R2 $NAME: FAIL (no server)"
    [ $NAME = r2_default ] && say "R2 /props build_info: $(curl -s -m 10 -H "Authorization: Bearer $(cat $NEWR/artifacts/api_key.txt)" http://127.0.0.1:8080/props | python -I -c "import json,sys; print(json.load(sys.stdin).get('build_info'))" 2>&1)"
  done ;;
r4)
  idx() { python -I -c "
import json,sys
idx={}
for l in open(sys.argv[1]):
    e=json.loads(l)
    if e.get('drop'): idx.pop(e['sha'],None)
    else: idx[e['sha']]=e
print(len(idx), 'entries;', sum(1 for e in idx.values() if e.get('parent')), 'deltas')" "$1"; }
  SG=$TEMP/r1105_slots_r4; rm -rf $SG; mkdir -p $SG
  if start r4 $NEWR BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 BONSAI_SLOT_SAVE_PATH="$(cygpath -w $SG)"; then
    PYTHONUTF8=1 python "$(cygpath -w $SP/r5_turns.py)" http://127.0.0.1:8080 "$(cygpath -m $NEWR/artifacts/api_key.txt)" "$(cygpath -w $SG)" 2>&1 | while read -r l; do say "R4 $l"; done
    PYTHONUTF8=1 python "$(cygpath -w $RD/../release-20261018f/r4_interleave.py)" http://127.0.0.1:8080 "$(cygpath -m $NEWR/artifacts/api_key.txt)" 2>&1 | while read -r l; do say "R4 $l"; done
    say "R4 index $(idx "$(cygpath -w $SG/lc-index.jsonl)"); CUDA errors $(cuda r4)"
  else say "R4: FAIL (no server)"; fi
  stopall; rm -rf $SG ;;
r3)
  BIAS=""; rm -f $RD/data/r3_*.jsonl $RD/data/r3c_*.jsonl
  if start r3_old $OLDR BONSAI_LAYER=0; then
    Z=--zero
    for b in 8 12 16; do
      S=$(PYTHONUTF8=1 python "$(cygpath -w $SP/eog_think_test.py)" --key-file "$KEY" --out "$(cygpath -w $RD/data/r3_old.jsonl)" --bias $b $Z 2>&1 | tee -a "$LOG" | grep '^summary'); Z=""
      say "R3 1026 $S"; o=$(echo "$S" | sed -E 's/.* open ([0-9]+) closed.*/\1/')
      [ "${o:-0}" -ge 3 ] 2>/dev/null && { BIAS=$b; break; }
    done
    PYTHONUTF8=1 python "$(cygpath -w $SP/agent_path.py)" --key-file "$KEY" --out "$(cygpath -w $RD/data/r3c_old.jsonl)" 2>&1 | sed 's/^/R3c 1026 /' | tee -a "$LOG"
  else say "R3 1026: FAIL (no server)"; fi
  if start r3_new $NEWR BONSAI_LAYER=0; then
    if [ -z "$BIAS" ]; then say "R3 the 1026 root never ended inside the block 3 of 5 times: the gate does not reach its trigger"
    else
      S=$(PYTHONUTF8=1 python "$(cygpath -w $SP/eog_think_test.py)" --key-file "$KEY" --out "$(cygpath -w $RD/data/r3_new.jsonl)" --bias $BIAS --zero 2>&1 | tee -a "$LOG" | grep '^summary')
      say "R3 candidate $S"
    fi
    PYTHONUTF8=1 python "$(cygpath -w $SP/agent_path.py)" --key-file "$KEY" --out "$(cygpath -w $RD/data/r3c_new.jsonl)" 2>&1 | sed 's/^/R3c candidate /' | tee -a "$LOG"
  else say "R3 candidate: FAIL (no server)"; fi
  say "R3 CUDA errors $(cuda r3_old) / $(cuda r3_new)" ;;
r5)
  for d in 4000 32000; do for tag in old new; do ROOT=$OLDR; [ $tag = new ] && ROOT=$NEWR; T=r5_${tag}_$d
    start $T $ROOT BONSAI_LAYER=0 || { say "R5 $T: FAIL (no server)"; continue; }
    QTPS_SAVE="$(cygpath -w $L/texts_r5_$tag)" PYTHONUTF8=1 python "$BENCH/quick_tps.py" --base http://127.0.0.1:8080 --key-file "$KEY" --depth $d 2>&1 \
      | grep -E "^(code|prose|bash) |mean decode|Error|Traceback" | sed "s/^/R5 $T: /" | tee -a "$LOG"
    [ $d = 4000 ] && PYTHONUTF8=1 python "$(cygpath -w $SP/think_texts.py)" --base http://127.0.0.1:8080 --key-file "$KEY" --out "$(cygpath -w $L/think_$tag)" 2>&1 | sed "s/^/R5 $T think: /" | tee -a "$LOG"
    say "R5 $T: mem $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader); CUDA errors $(cuda $T)"
  done; done
  stopall
  say "R5 file counts: thinking off $(ls $L/texts_r5_old/*.txt 2>/dev/null | wc -l) / $(ls $L/texts_r5_new/*.txt 2>/dev/null | wc -l) (need 6 / 6), thinking on $(ls $L/think_old/*.json 2>/dev/null | wc -l) / $(ls $L/think_new/*.json 2>/dev/null | wc -l) (need 6 / 6)"
  n=0; bad=0; for f in $L/texts_r5_old/*.txt; do n=$((n+1)); cmp -s "$f" "$L/texts_r5_new/$(basename $f)" || { bad=$((bad+1)); say "R5 text $(basename $f): DIFFER"; }; done; say "R5 texts (thinking off): $((n-bad)) / $n identical"
  say "R5 thinking on: $(python -I "$(cygpath -w $SP/think_texts.py)" --compare "$(cygpath -w $L/think_old)" "$(cygpath -w $L/think_new)" | tr '\n' ' ')"
  mkdir -p $RD/data/think_old $RD/data/think_new; cp $L/think_old/*.json $RD/data/think_old/; cp $L/think_new/*.json $RD/data/think_new/ ;;
r6)
  if start r6 $NEWR BONSAI_LAYER=0; then
    PYTHONUTF8=1 python "$BENCH/humaneval_run.py" --key-file "$KEY" --arm medium --max-tokens 24576 --out "$(cygpath -w $L/humaneval-1105)" 2>&1 | tail -2 | sed 's/^/R6 /' | tee -a "$LOG"
    say "R6 empty answers: $(python -I -c "
import json,sys
n=0
for l in open(sys.argv[1], encoding='utf-8'):
    r=json.loads(l)
    t=r.get('completion') or r.get('content') or r.get('response') or ''
    n+= not str(t).strip()
print(n)" "$(cygpath -w $L/humaneval-1105/samples.jsonl)"); CUDA errors $(cuda r6)"
    mkdir -p $RD/data/humaneval-1105 && cp $L/humaneval-1105/summary.json $RD/data/humaneval-1105/
  else say "R6: FAIL (no server)"; fi ;;
esac; done
stopall
say "=== release-20261105 [$STEPS] done"
