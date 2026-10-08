#!/usr/bin/env bash
# Tiered-KV engine A/B with the VRAM line pinned low, so short prompts run past it. Per arm: one quick_tps prefill to
# <depth> with the cost of each 2,048-token prefill chunk (server log), then greedy text past the line (lookup_ab.py,
# quote + plain at 30k). The summary compares the text of every arm with the first arm.
#   bash bench/tier_ab.sh <depth> <arm> ...    arm = name|root|VAR=value,VAR=value   (root "repo" = this repository)
#   -> receipts/tier_ab.log, receipts/tier_ab.jsonl
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; DEPTH="${1:-40000}"; shift
LOG=receipts/tier_ab.log; OUT=receipts/tier_ab.jsonl
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
ours() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$1"; }
TAGS=()
say "=== tier A/B, depth $DEPTH"
for A in "$@"; do
  IFS='|' read -r NAME ROOT VARS <<< "$A"
  [ "$ROOT" = repo ] && ROOT="$REPO"
  stop_srv
  ENVS=(BONSAI_MODEL="$MODEL" BONSAI_LAYER=0)
  IFS=',' read -ra KV <<< "$VARS"; for kv in "${KV[@]}"; do [ -n "$kv" ] && ENVS+=("$kv"); done
  env "${ENVS[@]}" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\tierab.$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\tierab.$NAME.server.log'"
  ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  ours "$ROOT" || ok=0
  say "arm $NAME ($ROOT; $VARS): health=$ok; $(grep '^kv' logs/tierab.$NAME.launcher.log)"
  [ $ok = 1 ] || continue
  PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $DEPTH 2>&1 | grep -m1 "depth" | sed "s/^/$NAME: /" | tee -a "$LOG"
  grep "prompt processing, n_tokens" logs/tierab.$NAME.server.log | sed -E 's/.*n_tokens = +([0-9]+).*t = +([0-9.]+) s.*/\1 \2/' \
    | awk -v n="$NAME" 'NR>1 && $1>pn {d=$1-pn; dt=$2-pt; printf "%s chunk to %6d: %.3f ms/tok\n", n, $1, 1000*dt/d} {pn=$1; pt=$2}' | tee -a "$LOG"
  LOOKUP_KINDS=quote,plain PYTHONUTF8=1 python bench/lookup_ab.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt \
    --tag "tierab-$NAME" --out $OUT --depth 30000 > /dev/null 2>&1
  TAGS+=("tierab-$NAME")
done
stop_srv
PYTHONUTF8=1 python - "${TAGS[@]}" <<'PY' | tee -a "$LOG"
import json, sys, collections
tags = sys.argv[1:]
rows = [json.loads(l) for l in open("receipts/tier_ab.jsonl", encoding="utf-8")]
by = collections.defaultdict(dict)
for r in rows:
    if r["tag"] in tags:
        by[(r["kind"], r["item"])][r["tag"]] = r
for t in tags[1:]:
    pairs = [(d[tags[0]]["sha"], d[t]["sha"]) for d in by.values() if tags[0] in d and t in d]
    same = sum(a == b for a, b in pairs)
    print(f"greedy text {t} vs {tags[0]}: {same}/{len(pairs)} identical")
for t in tags:
    v = [d[t]["tps"] for d in by.values() if t in d]
    print(f"{t}: decode mean {sum(v)/max(len(v),1):.1f} tok/s over {len(v)} jobs")
PY
say "=== done"
