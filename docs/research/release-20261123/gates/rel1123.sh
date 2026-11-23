#!/usr/bin/env bash
# release-20261123 R1-R6 on the zips (gates: docs/research/release-20261123/README.md, declared before the runs).
#   bash rel1123.sh <serve checkout with models/ and artifacts/release/> [steps, default "r1 r2 r4 r3c r5 r6"]
# Based on release-20261105/gates/rel1105.sh (fresh unzip per run, clean logs, POSIX paths, FAIL lines).
B=${1:?serve checkout}; STEPS=${2:-r1 r2 r4 r3c r5 r6}
SP=$(dirname "$(realpath "$0")"); RD=$(dirname "$SP"); BENCH=$(realpath "$RD/../../../bench"); G05=$(realpath "$RD/../release-20261105/gates")
cd "$B" || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
ZIP=$B/artifacts/release/bonsai-bundle-win-x64-20261123.zip; OLDZ=$B/artifacts/release/bonsai-bundle-win-x64-20261105.zip
TU=$(cygpath -u "$TEMP"); NEWR=$TU/r-1123z; OLDR=$TU/r-1105a; L=$TU/r1123-logs-${STEPS// /-}; rm -rf "$L"; mkdir -p "$L" "$RD/data"
LOG=$RD/data/release_1123.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $BENCH/stop_serve.ps1)" >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -like '*r-11*bonsai_layer.py*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"; }
trap stopall EXIT
unz() { rm -rf "$2"; mkdir -p "$2"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $1)" "$(cygpath -w $2)"
  [ -d "$2/layer/runtime" ] || cp -r $B/layer/runtime "$2/layer/"; mkdir -p "$2/artifacts" && cp artifacts/api_key.txt "$2/artifacts/api_key.txt"; }
unz $ZIP $NEWR; unz $OLDZ $OLDR   # always fresh: no folder of an earlier run
KEY="$(cygpath -w $NEWR/artifacts/api_key.txt)"
# start NAME ROOT ENV...: fresh server from ROOT's own launcher; health; owner check (8080 with the layer off, 18080 behind it)
start() { local NAME=$1 ROOT=$2; shift 2; stopall; sleep 4
  local OP=18080; case " $* " in *" BONSAI_LAYER=0 "*) OP=8080 ;; esac
  env BONSAI_MODEL="$MODEL" "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $ROOT)\start-server.ps1' -RedirectStandardOutput '$(cygpath -w $L)\\$NAME.launcher.log' -RedirectStandardError '$(cygpath -w $L)\\$NAME.server.log'" </dev/null >/dev/null 2>&1
  local ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $BENCH/serve_owner.ps1)" -Root "$(cygpath -w $ROOT)" -Port $OP >/dev/null || ok=0
  say "server $NAME ($(basename $ROOT) $*): health=$ok; $(grep -E '^(window |spec |layer |kv |note )|layer log:' $L/$NAME.launcher.log | tr -d '\r' | cut -c1-100 | tr '\n' '|')"; [ $ok = 1 ]; }
cuda() { grep -c 'CUDA error' $L/$1.server.log; }
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $NEWR/artifacts/api_key.txt)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours and one fact about each."}],"max_tokens":60,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:200].replace(chr(10),' '))" 2>&1; }
props() { curl -s -m 10 -H "Authorization: Bearer $(cat $NEWR/artifacts/api_key.txt)" http://127.0.0.1:8080/props | python -I -c "import json,sys; p=json.load(sys.stdin); print(p.get('build_info'), 'n_ctx', (p.get('default_generation_settings') or {}).get('n_ctx'))" 2>&1; }

for STEP in $STEPS; do case $STEP in
r1)
  say "=== release-20261123: zip sha256 $(python -I -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:16])" "$(cygpath -w $ZIP)"), engine $("$NEWR/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*\|([0-9a-f]*)' | head -1); 1105 root $("$OLDR/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*\|([0-9a-f]*)' | head -1)"
  say "R1 $(python -I -c "
import zipfile,re,sys,getpass
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
na=set(n for n in a.namelist() if not n.endswith('/')); nb=set(n for n in b.namelist() if not n.endswith('/'))
oa=set(n for n in na if not n.startswith('docs/')); ob=set(n for n in nb if not n.startswith('docs/'))
u=getpass.getuser().encode().lower()
print('outside docs: only-new', sorted(oa-ob), 'only-old', sorted(ob-oa), 'changed', sorted(n for n in oa&ob if a.read(n)!=b.read(n)),
      '| docs changed', sorted(n for n in (na-oa)&(nb-ob) if a.read(n)!=b.read(n)), 'docs new', sorted((na-oa)-(nb-ob)),
      '| control-byte files', len([n for n in na if n.endswith(('.ps1','.py','.md','.sh','.txt','.json','.jinja','.html')) and re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', a.read(n))]),
      '| entries with the user name', len([n for n in na if u in a.read(n).lower()]))" "$(cygpath -w $ZIP)" "$(cygpath -w $OLDZ)")"
  say "P1 private strings: $(python -I -c "
import zipfile,sys,getpass
u=getpass.getuser().lower()
pats=[u.encode(), ('users'+chr(92)+u).encode(), ('users/'+u).encode(), b'escha-port', b'l0xre', b'mirai-s-serve', b'wt-btier', b'wt-brel', ('projects'+chr(92)+'bnr').encode(), ('projects'+chr(92)+'wt-').encode()]
for zp in sys.argv[1:3]:
    z=zipfile.ZipFile(zp); hits={}
    for n in z.namelist():
        if n.endswith('/'): continue
        d=z.read(n).lower()
        for q in pats:
            if q in d: hits.setdefault(n, []).append(q.decode())
    print(zp.split(chr(92))[-1], len(hits), 'entries with hits', sorted(hits)[:12], '|')" "$(cygpath -w $ZIP)" "$(cygpath -w $OLDZ)")"
  say "R1 unzipped bin/ = zip entries: $(python -I -c "
import zipfile,hashlib,os,sys
z=zipfile.ZipFile(sys.argv[1]); bad=[n for n in z.namelist() if n.startswith('bin/') and not n.endswith('/') and hashlib.sha256(z.read(n)).digest()!=hashlib.sha256(open(os.path.join(sys.argv[2],*n.split('/')),'rb').read()).digest()]
print('all equal' if not bad else 'DIFFER '+' '.join(bad))" "$(cygpath -w $ZIP)" "$(cygpath -w $NEWR)")" ;;
r2)
  for arm in "default|BONSAI_LAYER=0 LLAMA_ARG_LOG_VERBOSITY=4" "8gb|BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 LLAMA_ARG_LOG_VERBOSITY=4" "8gb_r0|BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_RS_REPLAY=0 BONSAI_KV_VRAM_CELLS=90112 LLAMA_ARG_LOG_VERBOSITY=4" "24gb|BONSAI_LAYER=0 BONSAI_TOTAL_MIB=24576 LLAMA_ARG_LOG_VERBOSITY=4" "ctxg|BONSAI_LAYER=0 BONSAI_CTX=100000"; do
    NAME=r2_${arm%%|*}; ENVS=${arm#*|}
    start $NAME $NEWR $ENVS && { sleep 10; A=$(ask); say "R2 $NAME: answer: ${A:0:80}; CUDA errors $(cuda $NAME); replay: $(grep -h -o 'pending inputs of [0-9]* tokens' $L/$NAME.server.log | head -1)"; } || say "R2 $NAME: FAIL (no server)"
    case $NAME in r2_default|r2_ctxg) say "R2 $NAME /props: $(props)";; esac
    [ $NAME = r2_ctxg ] && say "R2 ctxg launcher: $(grep -h -E 'rounded up|^window ' $L/$NAME.launcher.log | tr -d '\r' | tr '\n' '|'); server n_ctx line: $(grep -h -o 'n_ctx *= *[0-9]*' $L/$NAME.server.log | head -1)"
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
  SG=$TU/r1123_slots_r4; rm -rf $SG; mkdir -p $SG
  if start r4 $NEWR BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=90112 BONSAI_SLOT_SAVE_PATH="$(cygpath -w $SG)"; then
    PYTHONUTF8=1 python "$(cygpath -w $G05/r5_turns.py)" http://127.0.0.1:8080 "$(cygpath -m $NEWR/artifacts/api_key.txt)" "$(cygpath -w $SG)" 2>&1 | while read -r l; do say "R4 $l"; done
    PYTHONUTF8=1 python "$(cygpath -w $RD/../release-20261018f/r4_interleave.py)" http://127.0.0.1:8080 "$(cygpath -m $NEWR/artifacts/api_key.txt)" 2>&1 | while read -r l; do say "R4 $l"; done
    say "R4 index $(idx "$(cygpath -w $SG/lc-index.jsonl)"); CUDA errors $(cuda r4)"
  else say "R4: FAIL (no server)"; fi
  stopall; rm -rf $SG ;;
r3c)
  rm -f $RD/data/r3c_*.jsonl
  for tag in old new; do ROOT=$OLDR; [ $tag = new ] && ROOT=$NEWR
    if start r3c_$tag $ROOT BONSAI_LAYER=0; then
      PYTHONUTF8=1 python "$(cygpath -w $G05/agent_path.py)" --key-file "$KEY" --out "$(cygpath -w $RD/data/r3c_$tag.jsonl)" 2>&1 | sed "s/^/R3c $tag /" | tee -a "$LOG"
      say "R3c $tag CUDA errors $(cuda r3c_$tag)"
    else say "R3c $tag: FAIL (no server)"; fi
  done ;;
r5)
  REP=${R5_REP:-1}
  for d in ${R5_DEPTHS:-4000 32000}; do for tag in old new; do ROOT=$OLDR; [ $tag = new ] && ROOT=$NEWR; T=r5_${tag}_${d}_$REP
    start $T $ROOT BONSAI_LAYER=0 || { say "R5 $T: FAIL (no server)"; continue; }
    QTPS_SAVE="$(cygpath -w $L/texts_r5_${tag}_$REP)" PYTHONUTF8=1 python "$BENCH/quick_tps.py" --base http://127.0.0.1:8080 --key-file "$KEY" --depth $d 2>&1 \
      | grep -E "^(code|prose|bash) |mean decode|Error|Traceback" | sed "s/^/R5 $T: /" | tee -a "$LOG"
    [ $d = 4000 ] && [ $REP = 1 ] && PYTHONUTF8=1 python "$(cygpath -w $G05/think_texts.py)" --base http://127.0.0.1:8080 --key-file "$KEY" --out "$(cygpath -w $L/think_$tag)" 2>&1 | sed "s/^/R5 $T think: /" | tee -a "$LOG"
    say "R5 $T: mem $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader); CUDA errors $(cuda $T)"
  done; done
  stopall
  say "R5 file counts: thinking off $(ls $L/texts_r5_old_$REP/*.txt 2>/dev/null | wc -l) / $(ls $L/texts_r5_new_$REP/*.txt 2>/dev/null | wc -l) (need 6 / 6), thinking on $(ls $L/think_old/*.json 2>/dev/null | wc -l) / $(ls $L/think_new/*.json 2>/dev/null | wc -l) (need 6 / 6)"
  n=0; bad=0; for f in $L/texts_r5_old_$REP/*.txt; do n=$((n+1)); cmp -s "$f" "$L/texts_r5_new_$REP/$(basename $f)" || { bad=$((bad+1)); say "R5 text $(basename $f): DIFFER"; }; done; say "R5 texts (thinking off): $((n-bad)) / $n identical"
  if [ $REP = 1 ]; then
    say "R5 thinking on: $(python -I "$(cygpath -w $G05/think_texts.py)" --compare "$(cygpath -w $L/think_old)" "$(cygpath -w $L/think_new)" | tr '\n' ' ')"
    mkdir -p $RD/data/think_old $RD/data/think_new $RD/data/texts_r5_old $RD/data/texts_r5_new
    cp $L/think_old/*.json $RD/data/think_old/; cp $L/think_new/*.json $RD/data/think_new/
    cp $L/texts_r5_old_1/*.txt $RD/data/texts_r5_old/; cp $L/texts_r5_new_1/*.txt $RD/data/texts_r5_new/
  fi ;;
r6)
  if start r6 $NEWR BONSAI_LAYER=0; then
    PYTHONUTF8=1 python "$BENCH/humaneval_run.py" --key-file "$KEY" --arm medium --max-tokens 24576 --out "$(cygpath -w $L/humaneval-1123)" < /dev/null 2>&1 | tail -2 | sed 's/^/R6 /' | tee -a "$LOG"
    say "R6 empty answers: $(python -I -c "
import json,sys
n=0
for l in open(sys.argv[1], encoding='utf-8'):
    r=json.loads(l)
    t=r.get('completion') or r.get('content') or r.get('response') or ''
    n+= not str(t).strip()
print(n)" "$(cygpath -w $L/humaneval-1123/samples.jsonl)"); CUDA errors $(cuda r6)"
    mkdir -p $RD/data/humaneval-1123 && cp $L/humaneval-1123/summary.json $RD/data/humaneval-1123/
    cp $L/r6.launcher.log $L/r6.server.log $RD/data/humaneval-1123/ 2>/dev/null
  else say "R6: FAIL (no server)"; fi ;;
esac; done
stopall
say "servers left: $(powershell -NoProfile -Command "(Get-Process llama-server -ErrorAction SilentlyContinue | Measure-Object).Count"); VRAM used $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
say "=== release-20261123 [$STEPS] done"
