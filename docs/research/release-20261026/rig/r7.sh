#!/usr/bin/env bash
# release-20261026 R7 on the RTX 2060 SUPER (P229). Run from the repo root in Git Bash, with no other server running.
#   bash docs/research/release-20261026/rig/r7.sh <1025 root> <1026 root> <model .gguf> <api key file> <out folder>
# Each root is an unzipped bundle with llama-perplexity.exe + llama-perplexity-impl.dll of its own engine in bin/.
# R7a: llama-perplexity logit files of the two roots, byte compare (q3_0 and q4_0 K/V; -ub 512 / 1 / 4 / 8).
# R7b: the 8 GB launcher (BONSAI_8GB=1, layer off), fresh server per depth and root, quick_tps at 64k and 128k.
set -u
OLD="$1"; NEW="$2"; MODEL="$3"; KEY="$4"; OUT="$5"; REPO="$(pwd)"
mkdir -p "$OUT"; LOG="$OUT/r7.log"; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
TXT="$REPO/artifacts/eval/wiki.test.raw"
[ -f "$TXT" ] || { say "need $TXT (wikitext-2 test split)"; exit 1; }
for r in "$OLD" "$NEW"; do [ -f "$r/bin/llama-perplexity.exe" ] || { say "no llama-perplexity in $r/bin"; exit 1; }; done
say "start; GPU: $(nvidia-smi --query-gpu=name,driver_version,memory.used,clocks.max.mem --format=csv,noheader)"
say "1025 engine: $("$OLD/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')  1026 engine: $("$NEW/bin/llama-server.exe" --version 2>&1 | grep -o 'commit [0-9a-f]*')"

# R7a
export GGML_CUDA_BATCH_INVARIANT=1
for kv in q3_0 q4_0; do for cell in "8192 2 512" "2048 1 1" "2048 1 4" "2048 1 8"; do
  set -- $cell; c=$1; n=$2; ub=$3
  for tag in old new; do R="$OLD"; [ $tag = new ] && R="$NEW"
    "$R/bin/llama-perplexity.exe" -m "$MODEL" -f "$(cygpath -w "$TXT")" -c $c --chunks $n -ngl 99 -fa on -ctk $kv -ctv $kv -b $c -ub $ub \
      --kl-divergence-base "$(cygpath -w "$OUT/kl_$tag.bin")" > "$OUT/ppl_${kv}_${c}_${ub}_$tag.out" 2>&1
  done
  if cmp -s "$OUT/kl_old.bin" "$OUT/kl_new.bin"; then r=identical; else r=DIFFER; fi
  say "R7a $kv ctx $c ub $ub: $r ($(grep -o 'Final estimate: PPL = [0-9.]*' "$OUT/ppl_${kv}_${c}_${ub}_new.out"); size $(stat -c %s "$OUT/kl_new.bin"))"
  rm -f "$OUT/kl_old.bin" "$OUT/kl_new.bin"
done; done
unset GGML_CUDA_BATCH_INVARIANT

# R7b
stop_srv() { powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$REPO/bench/stop_serve.ps1")" >/dev/null 2>&1; }
for d in 64000 128000; do for tag in old new; do
  ROOT="$OLD"; [ $tag = new ] && ROOT="$NEW"; T=r7b_${tag}_$d
  stop_srv; mkdir -p "$ROOT/artifacts" && cp "$KEY" "$ROOT/artifacts/api_key.txt"
  LL="$(cygpath -w "$OUT/$T.launcher.log")"; SL="$(cygpath -w "$OUT/$T.server.log")"; SS="$(cygpath -w "$ROOT/start-server.ps1")"
  env BONSAI_MODEL="$(cygpath -w "$MODEL")" BONSAI_LAYER=0 BONSAI_8GB=1 powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$SS' -RedirectStandardOutput '$LL' -RedirectStandardError '$SL'" </dev/null >/dev/null 2>&1
  ok=0; for i in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$REPO/bench/serve_owner.ps1")" -Root "$(cygpath -w "$ROOT")" >/dev/null || ok=0
  say "=== $T: health=$ok; $(grep -E '^(kv|8gb) ' "$OUT/$T.launcher.log" | tr -d '\r' | cut -c1-150 | tr '\n' ' ')"
  [ $ok = 1 ] || { say "$T: no health, skipped"; continue; }
  QTPS_SAVE="$(cygpath -w "$OUT/texts_$tag")" PYTHONUTF8=1 python "$REPO/bench/quick_tps.py" --base http://127.0.0.1:8080 --key-file "$(cygpath -w "$KEY")" --depth $d 2>&1 \
    | grep -E "^(code|prose|bash) |mean decode|Error|Traceback" | sed "s/^/$T: /" | tee -a "$LOG"
  say "$T: memory clock under load $(nvidia-smi --query-gpu=clocks.mem --format=csv,noheader)"
  stop_srv
  say "$T: CUDA errors $(grep -c 'CUDA error' "$OUT/$T.server.log"), spill lines $(grep -c -i 'spill' "$OUT/$T.server.log")"
done; done
for f in "$OUT"/texts_old/*.txt; do b=$(basename "$f"); cmp -s "$f" "$OUT/texts_new/$b" && r=identical || r=DIFFER; say "R7b text $b: $r"; done
say "=== done"
