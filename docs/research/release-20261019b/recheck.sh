#!/usr/bin/env bash
# release-20261019b recheck after the docs/8gb/README.md fix: the new zip differs from the gated zip only there;
# R1 again; R2's RS buffer and replay line, measured with log verbosity 4.
SP=<scratchpad>/rel1019b
B=<checkout>; LOG=$SP/release_1019b.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
Z=$B/artifacts/release/bonsai-bundle-win-x64-20261019b.zip
cp $Z $SP/gated.zip
cd <checkout> || exit 1
HEAD=$(git rev-parse launcher/8gb-replay-2-2)
rm -rf $TEMP/rel-1019b-src && mkdir -p $TEMP/rel-1019b-src && git archive launcher/8gb-replay-2-2 | tar -x -C $TEMP/rel-1019b-src
echo "$HEAD" > $SP/archived_head.txt
python "$(cygpath -w $SP/make_bundle_1019b.py)" > $SP/bundle.out 2>&1
say "recheck: archive $HEAD; $(grep -E '^(broken|size)' $SP/bundle.out | tr '\n' ' ')"
say "recheck: new zip against the gated zip: $(python -I -c "
import zipfile,sys
a=zipfile.ZipFile(sys.argv[1]); b=zipfile.ZipFile(sys.argv[2])
na=set(n for n in a.namelist() if not n.endswith('/')); nb=set(n for n in b.namelist() if not n.endswith('/'))
print('only-new', sorted(na-nb), 'only-old', sorted(nb-na), 'changed', sorted(n for n in na&nb if a.read(n)!=b.read(n)))" "$(cygpath -w $Z)" "$(cygpath -w $SP/gated.zip)")"
say "recheck R1 control-byte files: $(python -I -c "
import zipfile,re,sys
a=zipfile.ZipFile(sys.argv[1])
print(sum(1 for n in a.namelist() if n.endswith(('.ps1','.py','.md','.sh','.txt','.json','.jinja','.html')) and re.search(rb'[\x00-\x08\x0b\x0c\x0e-\x1f]', a.read(n))))" "$(cygpath -w $Z)")"
U=$TEMP/r-1019bz; rm -rf "$U"; mkdir -p "$U"; python -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$(cygpath -w $Z)" "$(cygpath -w $U)"
mkdir -p "$U/artifacts" && cp $B/artifacts/api_key.txt "$U/artifacts/api_key.txt"
cd $B; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
for arm in "default|BONSAI_LAYER=0" "8gb|BONSAI_8GB=1 BONSAI_LAYER=0" "8gb_r0|BONSAI_8GB=1 BONSAI_LAYER=0 BONSAI_RS_REPLAY=0"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" LLAMA_ARG_LOG_VERBOSITY=4 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $U)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\r19c_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\r19c_$NAME.server.log'"
  ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "recheck R2 $NAME: health=$ok; $(grep -h '^spec' logs/r19c_$NAME.launcher.log | cut -c1-40); RS $(grep -h 'RS buffer size' logs/r19c_$NAME.server.log | head -1 | grep -o '[0-9.]* MiB'); replay line: $(grep -h -o 'replay rollback: [^:]*' logs/r19c_$NAME.server.log | head -1); CUDA errors $(grep -c 'CUDA error' logs/r19c_$NAME.server.log)"
done
stopall
say "=== recheck done"
