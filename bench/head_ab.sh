#!/usr/bin/env bash
# MTP head A/B on the served recipe: Q8_0 head (procreations) vs Q4_0 head (q4head). Same engine and launcher.
# Records the auto VRAM line, decode at the given depths (quick_tps), draft acceptance, greedy identity.
#   bash bench/head_ab.sh [depths]   -> receipts/head_ab.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; DEPTHS="${1:-4000 32000 100000}"; LOG=receipts/head_ab.log
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
ours() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$1"; }  # 8080 is served from <root>/bin
run() { # NAME MODEL-FILE
  stop_srv
  env BONSAI_MODEL="$2" BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\start-server.ps1' -RedirectStandardOutput '$REPO\logs\headab.$1.launcher.log' -RedirectStandardError '$REPO\logs\headab.$1.server.log'"
  local ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  ours "$REPO" || ok=0
  say "$1: health=$ok $(grep '^kv' logs/headab.$1.launcher.log)"
  [ $ok = 1 ] || return
  for d in $DEPTHS; do
    PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $d 2>&1 | grep "mean decode" | sed "s/^/$1 depth $d: /" | tee -a "$LOG"
  done
  grep "draft acceptance" logs/headab.$1.server.log | tail -3 | sed "s/.*draft acceptance/$1 acceptance/" | tee -a "$LOG"
  PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --tag "head-$1" --out receipts/head_ab.jsonl > /dev/null 2>&1
}
say "=== MTP head A/B: Q8_0 vs Q4_0, depths $DEPTHS"
run q8 Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf
run q4 Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf
run q8b Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf
run q4b Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf
stop_srv
PYTHONUTF8=1 python - <<'PY' | tee -a "$LOG"
import json, collections
rows = [json.loads(l) for l in open("receipts/head_ab.jsonl", encoding="utf-8")]
by = collections.defaultdict(dict)
for r in rows: by[(r["kind"], r["item"])][r["tag"]] = r
same = all(d.get("head-q4", {}).get("sha") == d.get("head-q8", {}).get("sha") for (k, i), d in by.items() if k != "edit")
print("greedy text, Q4_0 head vs Q8_0 head (quote + plain):", "identical" if same else "DIFFERS")
PY
say "=== done"
