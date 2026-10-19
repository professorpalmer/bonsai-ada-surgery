#!/usr/bin/env bash
B=%USERPROFILE%/Projects/bonsai-2-27b-serve; cd $B || exit 1; REPO="$(pwd -W)"; MODEL="$REPO\models\Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
U=$TEMP/r-1019z; RD=%USERPROFILE%/Projects/bonsai-rel1018/docs/research/release-20261019; LOG=$RD/release_1019.log; say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }
stopall() { powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; }
trap stopall EXIT
KEYU="$U/artifacts/api_key.txt"
ask() { curl -s -m 120 -H "Authorization: Bearer $(cat $KEYU)" -H "Content-Type: application/json" http://127.0.0.1:8080/v1/chat/completions -d '{"messages":[{"role":"user","content":"Name three primary colours and one fact about each."}],"max_tokens":60,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}' | python -I -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'][:200].replace(chr(10),' '))" 2>&1; }
for arm in "b8|" "b8r|BONSAI_RS_REPLAY=1"; do
  NAME=${arm%%|*}; ENVS=${arm#*|}; stopall; sleep 4
  env BONSAI_MODEL="$MODEL" BONSAI_8GB=1 BONSAI_TOTAL_MIB=8192 BONSAI_LAYER=0 LLAMA_ARG_LOG_VERBOSITY=4 $ENVS powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w $U)\start-server.ps1' -RedirectStandardOutput '$REPO\logs\r19_$NAME.launcher.log' -RedirectStandardError '$REPO\logs\r19_$NAME.server.log'"
  ok=0; for k in $(seq 1 150); do sleep 2; curl -s -m 2 http://127.0.0.1:8080/health | grep -q ok && { ok=1; break; }; done
  sleep 10; A=$(ask); echo "$A" > $TEMP/r19_ans_$NAME.txt
  L=$(grep -o 'cells 0\.\.[0-9]* in VRAM' logs/r19_$NAME.launcher.log | head -1 | grep -o '[0-9]*' | tail -1)
  say "R3b $NAME ($ENVS): health=$ok; line ${L:-none}; RS $(grep -h 'RS buffer size' logs/r19_$NAME.server.log | head -1 | grep -o '[0-9.]* MiB'); answer ${A:0:60}; CUDA errors $(grep -c 'CUDA error' logs/r19_$NAME.server.log)"
  echo "$L" > $TEMP/r19_line_$NAME.txt
done
say "R3b line diff $(( $(cat $TEMP/r19_line_b8r.txt) - $(cat $TEMP/r19_line_b8.txt) )); answers equal: $(cmp -s $TEMP/r19_ans_b8.txt $TEMP/r19_ans_b8r.txt && echo yes || echo NO)"
stopall
