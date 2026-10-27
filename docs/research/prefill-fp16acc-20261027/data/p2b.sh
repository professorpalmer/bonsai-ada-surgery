#!/usr/bin/env bash
# prefill-fp16acc-20261027 F0-F4 (docs/research/prefill-fp16acc-20261027/README.md). Waits for build_p2b.cmd.
SP=$(dirname "$(realpath "$0")"); P=<projects>; SERVE=$P/bonsai-2-27b-serve; REPO=$P/bonsai-saa
until grep -q "^=== done" "$SP/build_p2b.log" 2>/dev/null; do sleep 20; done
T=$(cygpath "$TEMP"); CTRL=$T/r-1026z; P2R=$T/r-p2b; B=$P/build-p2b/bin; BASEB=$P/build-rel1026/bin
LOG=$SP/p2b.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
cp $BASEB/cu*.dll $BASEB/nv*.dll $B/
rm -rf $P2R && cp -r $CTRL $P2R && cp $B/ggml-cuda.dll $P2R/bin/ggml-cuda.dll
say "roots: control $("$CTRL/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'), p2 $("$P2R/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*'); ggml-cuda.dll differs: $(cmp -s $CTRL/bin/ggml-cuda.dll $P2R/bin/ggml-cuda.dll && echo NO || echo yes); build $("$B/llama-perplexity.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
MODEL="$(cygpath -w $SERVE/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf)"; SMODEL="$(cygpath -w $SERVE/models/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf)"
TXT="$(cygpath -w $SERVE/artifacts/eval/wiki.test.raw)"; KEY=$SERVE/artifacts/api_key.txt

"$B/test-backend-ops.exe" -o FLASH_ATTN_EXT > "$SP/f0.out" 2>&1
say "F0 FLASH_ATTN_EXT: $(grep -E '[0-9]+/[0-9]+ tests passed' "$SP/f0.out" | tail -1); FAIL lines $(grep -c FAIL "$SP/f0.out")"
grep FAIL "$SP/f0.out" | head -5 | cut -c1-200 | sed 's/^/F0   /' | tee -a "$LOG"

export GGML_CUDA_BATCH_INVARIANT=1
"$BASEB/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c 8192 --chunks 2 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 8192 -ub 512 --kl-divergence-base "$(cygpath -w $SP/kl_base.bin)" > "$SP/f1_base.out" 2>&1
"$B/llama-perplexity.exe" -m "$MODEL" -f "$TXT" -c 8192 --chunks 2 -ngl 99 -fa on -ctk q4_0 -ctv q4_0 -b 8192 -ub 512 --kl-divergence-base "$(cygpath -w $SP/kl_base.bin)" --kl-divergence > "$SP/f1_p2.out" 2>&1
say "F1: $(grep -E 'Mean +KLD|Maximum KLD|Same top|Mean +PPL\(Q\)|Mean +PPL\(base\)' "$SP/f1_p2.out" | tr -s ' ' | tr '\n' ';')"
rm -f "$SP/kl_base.bin"; unset GGML_CUDA_BATCH_INVARIANT

stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $REPO/bench/stop_serve.ps1)" >/dev/null 2>&1; sleep 3; }
trap stop_srv EXIT
start_srv() { local ROOT=$1 N=$2; stop_srv; mkdir -p "$ROOT/artifacts" && cp "$KEY" "$ROOT/artifacts/api_key.txt"
  local LL="$(cygpath -w "$SP/$N.launcher.log")" SL="$(cygpath -w "$SP/$N.server.log")" SS="$(cygpath -w "$ROOT/start-server.ps1")"
  env BONSAI_MODEL="$SMODEL" BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$SS' -RedirectStandardOutput '$LL' -RedirectStandardError '$SL'" </dev/null >/dev/null 2>&1
  local ok=0; for i in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w $REPO/bench/serve_owner.ps1)" -Root "$(cygpath -w $ROOT)" >/dev/null || ok=0
  say "server $N: health=$ok; $(grep -E '^kv ' $SP/$N.launcher.log | tr -d '\r' | cut -c1-80); mem $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  [ $ok = 1 ]; }
for set in code prose; do for arm in ctrl p2; do R=$CTRL; [ $arm = p2 ] && R=$P2R; N=f2_${set}_$arm
  start_srv $R $N || continue
  PYTHONUTF8=1 python "$(cygpath -w $SP/drive.py)" --set $set --arm dense --key-file "$(cygpath -w $KEY)" --out "$(cygpath -w $SP/$N.jsonl)" < /dev/null > "$SP/$N.out" 2>&1
  say "F2 $N: $(python -c "import json,sys;r=[json.loads(l) for l in open(sys.argv[1],encoding='utf-8')];print('ok',sum(x['ok'] for x in r),'of',len(r),'| cold read',r[0].get('wall_s'),'s, prompt',r[0].get('prompt_n'),'tok,',r[0].get('prefill_tps'),'tok/s | errors',sum('error' in x for x in r))" "$(cygpath -w $SP/$N.jsonl)"); CUDA errors $(grep -c 'CUDA error' $SP/$N.server.log)"
  stop_srv
done; done
for d in 64000 128000; do for arm in ctrl p2; do R=$CTRL; [ $arm = p2 ] && R=$P2R; N=f4_${arm}_$d
  start_srv $R $N || continue
  QTPS_SAVE="$(cygpath -w $SP/texts_f4_$arm)" PYTHONUTF8=1 python "$REPO/bench/quick_tps.py" --base http://127.0.0.1:8080 --key-file "$(cygpath -w $KEY)" --depth $d 2>&1 \
    | grep -E "^(code|prose|bash) |mean decode|Error|Traceback" | sed "s/^/F4 $N: /" | tee -a "$LOG"
  stop_srv; say "F4 $N: CUDA errors $(grep -c 'CUDA error' $SP/$N.server.log)"
done; done
n=0; bad=0; for f in $SP/texts_f4_ctrl/*.txt; do n=$((n+1)); cmp -s "$f" "$SP/texts_f4_p2/$(basename $f)" || bad=$((bad+1)); done
say "F4 texts: $((n-bad)) / $n identical"
say "p2b done"
