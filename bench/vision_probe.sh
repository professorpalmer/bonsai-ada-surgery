#!/usr/bin/env bash
# Issue #4 follow-up (Milor123): the vision projector and the VRAM line. Four arms on the full 27B recipe, layer off,
# server on :8080: A no projector; B the old launcher with LLAMA_ARG_MMPROJ (the reported setup); C the new launcher,
# projector on the CPU (default); D the new launcher with BONSAI_MMPROJ_GPU=1 and the cache pinned to A's cells, so
# the VRAM difference is the projector's own cost. Per arm: VRAM at load, decode/prefill at 16k (bench/quick_tps.py),
# and for B-D one image request (logs/test_image.png). Output: receipts/vision_probe.log
cd "$(dirname "$0")/.." || exit 1
LOG=receipts/vision_probe.log; MM="Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
MODEL="Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf"
say() { echo "$(date '+%H:%M') $*" | tee -a "$LOG"; }
stop() { powershell -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like 'C:\Users\pwall\Projects\bonsai-2-27b-serve\*' } | Stop-Process -Force" >/dev/null 2>&1; sleep 4; }
arm() { # LABEL LAUNCHER "ENV"
  local label=$1 launcher=$2 envs=$3
  stop; rm -f logs/vp_launcher.log
  env BONSAI_MODEL="$MODEL" BONSAI_LAYER=0 $envs powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\pwall\Projects\bonsai-2-27b-serve\\$launcher' -RedirectStandardOutput 'C:\Users\pwall\Projects\bonsai-2-27b-serve\logs\vp_launcher.log' -RedirectStandardError 'C:\Users\pwall\Projects\bonsai-2-27b-serve\logs\vp_$label.err'"
  local ok=0 i; for i in $(seq 1 60); do sleep 3; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
  sleep 5
  say "arm $label: health=$ok vram_at_load=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader) $(grep -E '^kv' logs/vp_launcher.log | cut -c1-60) $(grep -E '^vision' logs/vp_launcher.log)"
  [ $ok = 1 ] || { tail -3 logs/vp_$label.err | tee -a "$LOG"; return; }
  PYTHONUTF8=1 python bench/quick_tps.py --base http://127.0.0.1:8080 --key-file artifacts/api_key.txt --depth 16000 2>&1 | grep -E "^code|^prose|mean decode" | tee -a "$LOG"
  say "   vram after 16k: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader); shared GPU memory is not visible here"
  if [ "$label" != A ]; then
    PYTHONUTF8=1 python - <<'PY' 2>&1 | tee -a "$LOG"
import base64, json, time, urllib.request
key = open("artifacts/api_key.txt", encoding="utf-8").read().strip()
img = base64.b64encode(open("logs/test_image.png", "rb").read()).decode()
body = {"model": "x", "max_tokens": 60, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False},
        "messages": [{"role": "user", "content": [{"type": "text", "text": "What shape and colors are in this image? One sentence."},
                                                    {"type": "image_url", "image_url": {"url": "data:image/png;base64," + img}}]}]}
t = time.time()
try:
    r = json.loads(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", json.dumps(body).encode(),
        {"Authorization": "Bearer " + key, "Content-Type": "application/json"}), timeout=600).read())
    print(f"   image request: {time.time()-t:.1f} s, answer: {r['choices'][0]['message']['content'][:120]!r}")
except Exception as e:
    print("   image request failed:", repr(e)[:200])
PY
  fi
}
say "=== vision probe $(bin/llama-server.exe --version 2>&1 | head -1 | cut -c1-60)"
arm A start-server.ps1 ""
CELLS=$(grep -oE 'cells 0\.\.[0-9]+' logs/vp_launcher.log | grep -oE '[0-9]+$')
arm B start-server.old.ps1 "LLAMA_ARG_MMPROJ=C:\\Users\\pwall\\Projects\\bonsai-2-27b-serve\\models\\$MM"
arm C start-server.ps1 "LLAMA_ARG_MMPROJ=C:\\Users\\pwall\\Projects\\bonsai-2-27b-serve\\models\\$MM"
arm D start-server.ps1 "BONSAI_MMPROJ=$MM BONSAI_MMPROJ_GPU=1 BONSAI_KV_VRAM_CELLS=$CELLS"
stop
say "=== done (A's cells: $CELLS)"
