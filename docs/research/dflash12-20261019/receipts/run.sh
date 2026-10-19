#!/usr/bin/env bash
# DFlash 2 drafter on the 12 GB preset (plan: bonsai-saa docs/research/dflash12-20261019/README.md).
# D0 probe (C and D at 4k, lowest free VRAM) -> D1 (fresh server per depth) -> control check (C at 4k and 128k).
B=<checkout>; cd $B || exit 1
SP=$(dirname "$(realpath "$0")"); LOG=$SP/dflash.log
ROOT="$(cygpath -w $TEMP/r-1019az)"
DRAFT="<models>/dflash-naklitechie/Qwen3.8-27B-DFlash2-r3-Q4_K_M.gguf"
say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4; }
dflash_env() { export BONSAI_SPEC_TYPE="ngram-mod,draft-dflash" BONSAI_SPEC_ARGS="-md $DRAFT -ngld 99"; }
plain_env() { unset BONSAI_SPEC_TYPE BONSAI_SPEC_ARGS BONSAI_VRAM_MARGIN; }

probe() {   # $1 name; env already set; prints the lowest free MiB during a 4k quick_tps
  stop_srv
  REPO="$(pwd -W)"; MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
  mkdir -p "$TEMP/r-1019az/artifacts" && cp artifacts/api_key.txt "$TEMP/r-1019az/artifacts/api_key.txt"
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\dflash_probe_$1.launcher.log' -RedirectStandardError '$REPO\\logs\\dflash_probe_$1.server.log'"
  ok=0; for i in $(seq 1 120); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  [ $ok = 1 ] || { say "probe $1: no health"; return 1; }
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" >/dev/null || { say "probe $1: the port is not served from the root"; return 1; }
  : > $SP/free_$1.txt
  ( while true; do nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits >> $SP/free_$1.txt; sleep 0.5; done ) &
  W=$!
  PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 4000 2>&1 \
    | grep -E "^(code|prose|bash) |mean decode" | sed "s/^/probe $1: /" | tee -a "$LOG"
  kill $W 2>/dev/null
  say "probe $1: lowest free $(sort -n $SP/free_$1.txt | head -1) MiB; $(grep -h -E '^(kv|spec|pool)' logs/dflash_probe_$1.launcher.log | cut -c1-90 | tr '\n' ' '); CUDA errors $(grep -c 'CUDA error' logs/dflash_probe_$1.server.log); dflash $(grep -c -i 'dflash' logs/dflash_probe_$1.server.log) lines"
  stop_srv
}

say "=== DFlash 12 GB: drafter $(sha256sum "$DRAFT" | cut -c1-16)"
plain_env; probe C
dflash_env; export BONSAI_VRAM_MARGIN=2400; probe D
FC=$(sort -n $SP/free_C.txt | head -1); FD=$(sort -n $SP/free_D.txt | head -1)
COST=$(( 1400 - (FD - FC) )); MD=$(( 1000 + COST ))
say "D0: free C $FC, D $FD (margin 2400) -> drafter cost $COST MiB -> D margin $MD"
[ $COST -gt 200 ] && [ $COST -lt 2400 ] || { say "D0: implausible cost, stop"; exit 1; }

dflash_env; export BONSAI_VRAM_MARGIN=$MD
for d in 4000 32000 64000 128000 192000 245000; do
  bash bench/depth_table.sh "$ROOT" dflash12-$d $d
  sleep 5
done
plain_env
for d in 4000 128000; do
  bash bench/depth_table.sh "$ROOT" dflash12-ctrl-$d $d
  sleep 5
done
say "=== DFlash 12 GB done"
