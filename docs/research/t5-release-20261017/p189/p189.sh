#!/usr/bin/env bash
# P189: drift score for the T5 window settings (#138 comment 6245198344). Arms: off, null, w32k, w64k, w32k sink 8k.
B=/c/Users/<user>/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")")
cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
LOG=$SP/p189.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
K="$(cygpath -m $TEMP/r-t5/artifacts/api_key.txt)"
say "=== P189: $("$TEMP/r-t5/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"
# arm name, then env assignments
run_arm() { local ARM=$1; shift
  for set in code prose; do
    local NAME=${ARM}_$set; stopall; sleep 4
    env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_8GB=1 BONSAI_KV_VRAM_CELLS=80640 "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $TEMP/r-t5)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\p189_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\p189_$NAME.server.log'"
    local ok=0; for k in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
    say "server $NAME ($*): health=$ok; $(grep -o 'deeper in chunks of [0-9]*' logs/p189_$NAME.launcher.log | head -1); window line: $(grep -o 'prefill window on[^\r]*' logs/p189_$NAME.server.log | head -1); clock $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
    [ $ok = 1 ] || continue
    PYTHONUTF8=1 python "$SP/p189_drive.py" --set $set --arm dense --key-file "$K" --out "$(cygpath -m $SP)/p189_$NAME.jsonl" < /dev/null > "$SP/p189_$NAME.out" 2>&1
    say "  $NAME: $(python -c "import json,sys;r=[json.loads(l) for l in open(sys.argv[1],encoding='utf-8')];print('ok',sum(x['ok'] for x in r),'of',len(r),'cold',r[0].get('wall_s'),'s, errors',sum('error' in x for x in r))" "$(cygpath -m $SP)/p189_$NAME.jsonl"); CUDA errors $(grep -c 'CUDA error' logs/p189_$NAME.server.log)"
  done
}
run_arm off
run_arm null GGML_CUDA_FA_CHUNK=16384
run_arm w32 LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024
run_arm w64 LLAMA_PREFILL_WINDOW=window=65536,sink=1024,tail=1024
run_arm w32s8 LLAMA_PREFILL_WINDOW=window=32768,sink=8192,tail=1024
stopall
say "=== P189 done"
