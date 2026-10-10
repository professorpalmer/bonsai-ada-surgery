#!/usr/bin/env bash
# Prefill cost of extra slots / a unified KV cache: fresh 32k prompt (quick_tps first line), 12 GB recipe, layer off.
#   bash bench/slots_prefill.sh <root with BONSAI_SLOTS support>   -> receipts/slots_prefill.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"; ROOT="$(cygpath -w "${1:?root}")"; LOG=receipts/slots_prefill.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
for A in "np1|BONSAI_VRAM_MARGIN=1300" "np1kvu|BONSAI_VRAM_MARGIN=1300 LLAMA_ARG_KV_UNIFIED=1" "np2|BONSAI_VRAM_MARGIN=1300 BONSAI_SLOTS=2" "np2kvu|BONSAI_VRAM_MARGIN=1300 BONSAI_SLOTS=2 LLAMA_ARG_KV_UNIFIED=1" "np1-again|BONSAI_VRAM_MARGIN=1300"; do
  NAME=${A%%|*}; ENVS=${A#*|}
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\start-server.ps1' -RedirectStandardOutput '$REPO\logs\slotspf_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\slotspf_$NAME.server.log'"
  ok=0; for k in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  [ $ok = 1 ] || { say "$NAME: no health"; continue; }
  say "$NAME ($ENVS): $(PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 32000 2>&1 | grep -E '^code|^mean' | tr '\n' ' ' | tr -s ' ' | cut -c1-200)"
done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
say "=== done"
