#!/usr/bin/env bash
# The README speed table for one serve root: the launcher's served recipe (layer off), one fresh prefill to the deepest
# depth (cumulative prefill at each depth from the server's progress lines), then quick_tps at each lower depth in
# descending order (each prompt shares the deeper prompt's filler prefix, so the server reuses the cache and only the
# question is new). Decode = the quick_tps "code" prompt (400 tokens, greedy, thinking off) and the mean of its three.
#   bash bench/depth_table.sh <root> <tag> [depths, deepest first]   -> receipts/depth_table_<tag>.log
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; ROOT="$1"; TAG="$2"; DEPTHS="${3:-258000 180000 131000 112000 64000 32000 16000 4000}"
[ "$ROOT" = repo ] && ROOT="$REPO"
LOG=receipts/depth_table_$TAG.log
MODEL="$REPO\\models\\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
stop_srv
# a clean unzip has no key: the launcher would make a new one, and every request would get 401
mkdir -p "$ROOT/artifacts" && cp artifacts/api_key.txt "$ROOT/artifacts/api_key.txt"
env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\depthtable.$TAG.launcher.log' -RedirectStandardError '$REPO\\logs\\depthtable.$TAG.server.log'"
ok=0; for i in $(seq 1 90); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
powershell -NoProfile -ExecutionPolicy Bypass -File bench/serve_owner.ps1 -Root "$ROOT" >/dev/null || ok=0
say "=== depth table $TAG ($ROOT): health=$ok; $(grep '^kv' logs/depthtable.$TAG.launcher.log)"
[ $ok = 1 ] || exit 1
for d in $DEPTHS; do
  PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth $d 2>&1 \
    | grep -E "^(code|prose|bash) |mean decode" | sed "s/^/$d: /" | tee -a "$LOG"
done
stop_srv
first=$(echo $DEPTHS | awk '{print $1}')
grep "prompt processing, n_tokens" logs/depthtable.$TAG.server.log | sed -E 's/.*n_tokens = +([0-9]+).*t = +([0-9.]+) s.*/\1 \2/' \
  | awk -v want="$DEPTHS" 'BEGIN { n = split(want, w, " ") } $1 > last { for (k = 1; k <= n; k++) if (!done[k] && $1 >= w[k] - 1024) { printf "cumulative prefill at %6d: %4.0f tok/s (%d tokens in %.1f s)\n", w[k], $1 / $2, $1, $2; done[k] = 1 } last = $1 }' \
  | sort -t: -k1,1 | tee -a "$LOG"
say "=== done"
