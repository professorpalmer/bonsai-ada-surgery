#!/usr/bin/env bash
# R3c: launcher sizing under an 8 GB-like free VRAM (ballast), replay off vs on.
B=%USERPROFILE%/Projects/bonsai-2-27b-serve; SP=$(dirname "$(realpath "$0")"); cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
U=$TEMP/r-1019z; RD=%USERPROFILE%/Projects/bonsai-rel1018/docs/research/release-20261019; LOG=$RD/release_1019.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
BL=$TEMP/r19_ballast.log; rm -f $BL
powershell -NoProfile -Command "\$p = Start-Process python -ArgumentList '$(cygpath -w $SP/ballast.py)','7600' -WindowStyle Hidden -RedirectStandardOutput '$(cygpath -w $BL)' -PassThru; \$p.Id" > $TEMP/r19_ballast.pid
for i in $(seq 1 60); do sleep 2; grep -q "ballast" $BL 2>/dev/null && break; done
say "R3c $(cat $BL) (pid $(cat $TEMP/r19_ballast.pid | tr -d '\r'))"
KEYU="$U/artifacts/api_key.txt"
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $KEYU)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours and one fact about each."}],"max_tokens":60,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:200].replace(chr(10),' '))" 2>&1; }
for arm in "c8|" "c8r|BONSAI_RS_REPLAY=1"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}; stopall; sleep 5
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_LAYER=0 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $U)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\r19_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\r19_$NAME.server.log'"
  ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  sleep 10; A=$(ask); echo "$A" > $TEMP/r19_ans_$NAME.txt
  L=$(grep -o 'cells 0\.\.[0-9]* in VRAM' logs/r19_$NAME.launcher.log | head -1 | grep -o '[0-9]*' | tail -1); echo "${L:-0}" > $TEMP/r19_line_$NAME.txt
  ( while true; do nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits; sleep 2; done ) > $TEMP/r19_free_$NAME.txt & MON=$!
  R=$(PYTHONUTF8=1 python "$SP/../replay/depth.py" http://127.0.0.1:8080 "$(cygpath -m $KEYU)" 128000 "$(cygpath -m $RD)/r3c.jsonl" $NAME 2>&1 | tail -1 | cut -c1-200)
  kill $MON 2>/dev/null
  say "R3c $NAME ($ENVS): health=$ok; line ${L:-none}; answer ${A:0:50}; 128k: $R; min free $(sort -n $TEMP/r19_free_$NAME.txt | head -1) MiB; CUDA errors $(grep -c 'CUDA error' logs/r19_$NAME.server.log)"
done
stopall
powershell -NoProfile -Command "Stop-Process -Id $(cat $TEMP/r19_ballast.pid | tr -d '\r') -Force -ErrorAction SilentlyContinue"
say "R3c line diff $(( $(cat $TEMP/r19_line_c8r.txt) - $(cat $TEMP/r19_line_c8.txt) )); answers equal: $(cmp -s $TEMP/r19_ans_c8.txt $TEMP/r19_ans_c8r.txt && echo yes || echo NO); free after $(nvidia-smi --query-gpu=memory.free --format=csv,noheader)"
