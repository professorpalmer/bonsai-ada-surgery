#!/usr/bin/env bash
# PR #19 open point: the 160k quote that differed with the chunk on. 12 GB recipe, bundle bin, drafting + lookup,
# quote items only at depth 160k, arms off / on / off / on, texts saved.
#   bash bench/pr19_quote160k.sh <root>   -> receipts/pr19_quote160k.{log,jsonl}, artifacts/pr19_quote160k/*.txt
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"
LOG=receipts/pr19_quote160k.log; OUT=receipts/pr19_quote160k.jsonl
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4; }
i=0
for A in off on off on; do
  i=$((i + 1)); C=0; [ $A = on ] && C=32768
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 GGML_CUDA_FA_CHUNK=$C powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\pr19q_$i.launcher.log' -RedirectStandardError '$REPO\logs\pr19q_$i.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  say "run $i chunk=$C health=$ok"
  [ $ok = 1 ] && LOOKUP_KINDS=quote LOOKUP_SAVE_DIR=artifacts/pr19_quote160k PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "r$i-$A" --out $OUT --depth 160000 2>&1 | tee -a "$LOG"
done
stop_srv
say "=== done"
