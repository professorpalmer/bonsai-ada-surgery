#!/usr/bin/env bash
# The 1-token answer bug from the 8 GB card (PR #9), on the RTX 4070: all-VRAM cache (64k window, layer off), fresh
# prompts at 20k-60k, arms "name|root|VAR=v,..." (root "repo" = this repo).
#   bash bench/one_token_ab.sh "q4-f16cap|repo|BONSAI_CTK=q4_0,GGML_CUDA_FA_PREFILL_F16=32768" ...
#   -> receipts/one_token_ab.log, receipts/one_token_repro.jsonl
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/one_token_ab.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
for A in "$@"; do
  IFS='|' read -r NAME ROOT VARS <<< "$A"
  [ "$ROOT" = repo ] && ROOT="$REPO"
  stop_srv
  ENVS=(BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_TIER=0 BONSAI_CTX=65536); IFS=',' read -ra VV <<< "$VARS"; for v in "${VV[@]}"; do [ -n "$v" ] && ENVS+=("$v"); done
  env "${ENVS[@]}" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\onetok.$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\onetok.$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" >/dev/null 2>&1 || { say "arm $NAME: 8080 is not served from $ROOT, stop"; ok=0; }
  say "arm $NAME ($VARS): health=$ok; $(grep '^kv\|^window' logs/onetok.$NAME.launcher.log | tr '\n' ' ' | cut -c1-160)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/one_token_repro.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "$NAME" 2>&1 | tee -a "$LOG"
done
stop_srv
say "=== done"
