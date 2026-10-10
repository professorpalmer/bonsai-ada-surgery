#!/usr/bin/env bash
# Issue #16: server private bytes and system commit during 7 sequential thinking requests (bench/ram_probe.py),
# 12 GB recipe at 262k (defaults vs LLAMA_ARG_CTX_CHECKPOINTS=8 + LLAMA_ARG_CACHE_RAM=1024), then Mirai S defaults.
# Layer off (requests go to the server directly). -> receipts/ram_ab.log, receipts/ram_ab.jsonl, logs/ram_<arm>.csv
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd -W)"; LOG=receipts/ram_ab.log; MIRAI=/c/Users/pwall/Projects/mirai-s-serve; MIRAIW="$(cd $MIRAI && pwd -W)"
N=${RAM_N:-7}; DEPTH=${RAM_DEPTH:-24000}
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop_all() { powershell -NoProfile -ExecutionPolicy Bypass -File "$MIRAI/tooling/stop.ps1" >/dev/null 2>&1; rm -f "$MIRAI/logs/product.stop"
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 3; }
wait_health() { for i in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && return 0; done; return 1; }
summary() { python - "$1" <<'EOF' | tee -a "$LOG"
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1])))
p = [int(r["server_private_mib"]) for r in rows if r["server_private_mib"]]
c = [float(r["commit_gib"]) for r in rows]
print(f"  samples {len(rows)}: server private start {p[0] if p else 0} MiB, peak {max(p) if p else 0} MiB; system commit start {c[0]:.2f}, peak {max(c):.2f} GiB (+{max(c)-c[0]:.2f})")
EOF
}
arm() { # name, root ("bonsai" or "mirai"), env...
  local NAME=$1 WHO=$2; shift 2
  stop_all
  rm -f logs/ram.stop
  powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\bench\\ram_sample.ps1','-Out','$REPO\\logs\\ram_$NAME.csv','-StopFile','$REPO\\logs\\ram.stop'"
  sleep 3
  if [ "$WHO" = bonsai ]; then
    env BONSAI_LAYER=0 "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$REPO\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\ram_$NAME.launcher.log' -RedirectStandardError '$REPO\\logs\\ram_$NAME.server.log'"
    KEY=artifacts/api_key.txt
  else
    (cd "$MIRAI" && env MIRAI_LAYER=0 MIRAI_LOG_FILE="logs/ram_$NAME.log" "$@" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$MIRAIW\\start-server.ps1' -RedirectStandardOutput '$REPO\\logs\\ram_$NAME.launcher.log'")
    KEY="$MIRAI/artifacts/api_key.txt"
  fi
  if wait_health; then
    say "arm $NAME ($*): health=1; $(grep '^kv\|^ckpt' logs/ram_$NAME.launcher.log | tr '\n' ' ' | cut -c1-200)"
    PYTHONUTF8=1 python bench/ram_probe.py --base http://127.0.0.1:8080 --key-file "$KEY" --n $N --depth $DEPTH --tag "$NAME" 2>&1 | tee -a receipts/ram_ab.jsonl | tee -a "$LOG"
  else say "arm $NAME: no health"; fi
  sleep 5
  touch logs/ram.stop; sleep 3
  summary "logs/ram_$NAME.csv"
}
say "=== ram_ab (Bonsai 12 GB, 32 GB tier: cache 4096, 32 checkpoints) start (n $N, depth $DEPTH)"


arm b12-tier32 bonsai LLAMA_ARG_CACHE_RAM=4096
stop_all
say "=== ram_ab finished"
