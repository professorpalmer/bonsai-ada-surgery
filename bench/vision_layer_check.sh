#!/usr/bin/env bash
# Vision through the layer (2026-10-14, a user report on X: "the serve layer doesn't accept images, rejecting requests
# instantly"). The 10-07 probe ran with the layer off. Two arms, launcher defaults (layer on, :8080 = the layer),
# product bin/: L0 no projector (what a default install answers to an image), L1 BONSAI_MMPROJ on the CPU (the
# documented opt-in). Per arm: one image request and one text request through :8080. -> docs/receipts/vision_layer.log
cd "$(dirname "$0")/.." || exit 1
LOG=docs/receipts/vision_layer.log; MM="Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
say() { echo "$(date '+%F %H:%M') $*" | tee -a "$LOG"; }
arm() { # LABEL "ENV"
  local label=$1 envs=$2
  powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1; sleep 3
  env $envs powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\pwall\Projects\bonsai-2-27b-serve\start-server.ps1' -RedirectStandardOutput 'C:\Users\pwall\Projects\bonsai-2-27b-serve\logs\vl_$label.launcher.log' -RedirectStandardError 'C:\Users\pwall\Projects\bonsai-2-27b-serve\logs\vl_$label.err'"
  local ok=0 i; for i in $(seq 1 80); do sleep 3; curl -s -m 2 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
  sleep 5
  say "arm $label ($envs): health=$ok; $(grep -E '^(layer|vision)' logs/vl_$label.launcher.log | tr '\n' ' ' | cut -c1-200)"
  [ $ok = 1 ] || { tail -3 logs/vl_$label.err | tee -a "$LOG"; return; }
  PYTHONUTF8=1 python - <<'PY' 2>&1 | tee -a "$LOG"
import base64, json, time, urllib.request, urllib.error
key = open("artifacts/api_key.txt", encoding="utf-8").read().strip()
img = base64.b64encode(open("logs/test_image.png", "rb").read()).decode()
def ask(content, what):
    body = {"model": "x", "max_tokens": 80, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False},
            "messages": [{"role": "user", "content": content}]}
    t = time.time()
    try:
        r = json.loads(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8080/v1/chat/completions", json.dumps(body).encode(),
            {"Authorization": "Bearer " + key, "Content-Type": "application/json"}), timeout=600).read())
        print(f"   {what}: {time.time()-t:.1f} s, answer: {r['choices'][0]['message']['content'][:120]!r}")
    except urllib.error.HTTPError as e:
        print(f"   {what}: HTTP {e.code} after {time.time()-t:.1f} s: {e.read()[:300]!r}")
    except Exception as e:
        print(f"   {what}: failed: {repr(e)[:200]}")
ask([{"type": "text", "text": "What shape and colors are in this image? One sentence."},
     {"type": "image_url", "image_url": {"url": "data:image/png;base64," + img}}], "image request")
ask("Say OK.", "text request")
PY
}
say "=== vision through the layer, $(bin/llama-server.exe --version 2>&1 | head -1 | cut -c1-60)"
arm L0 ""
arm L1 "BONSAI_MMPROJ=$MM"
powershell -NoProfile -ExecutionPolicy Bypass -File bench/stop_serve.ps1 >/dev/null 2>&1
say "=== done"
