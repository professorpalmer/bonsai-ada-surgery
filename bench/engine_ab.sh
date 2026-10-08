#!/usr/bin/env bash
# Engine A/B on the served recipe: the product bin (A) against a candidate root (B: its own bin\, same launcher,
# same model). Alternated A B A B, MTP on and off, quick_tps at the given depths; then greedy identity
# (release_smoke.sh). Layer off.
#   bash bench/engine_ab.sh <candidate-root> <tag> [depths]   -> receipts/engine_ab_<tag>.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; CAND="$1"; TAG="$2"; DEPTHS="${3:-4000 32000}"; LOG="receipts/engine_ab_$TAG.log"
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
ours() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$1"; }  # 8080 is served from <root>/bin
run() { # NAME ROOT SPEC
  local name=$1 root=$2 spec=$3
  stop_srv
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 BONSAI_SPEC="$spec" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$root\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\ab_$TAG.$name.launcher.log' -RedirectStandardError '$REPO\\logs\\ab_$TAG.$name.server.log'"
  local ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  ours "$root" || ok=0
  [ $ok = 1 ] || { say "$name: health=0"; return; }
  for d in $DEPTHS; do
    PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $d 2>&1 | grep "mean decode" | sed "s/^/$name depth $d: /" | tee -a "$LOG"
  done
}
say "=== engine A/B $TAG: A = $REPO\\bin, B = $CAND\\bin, depths $DEPTHS"
for spec in "" 0; do
  label=$([ -z "$spec" ] && echo mtp || echo nomtp)
  run "A-$label-1" "$REPO" "$spec"; run "B-$label-1" "$CAND" "$spec"
  run "A-$label-2" "$REPO" "$spec"; run "B-$label-2" "$CAND" "$spec"
done
stop_srv
say "greedy identity (release_smoke):"
bash bench/release_smoke.sh "$CAND" "ab_$TAG" 2>&1 | grep -E "identical|GREEDY" | tee -a "$LOG"
say "=== done"
