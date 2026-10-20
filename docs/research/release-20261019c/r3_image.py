"""R3: an image in a tool message, server without mmproj: through the layer (:8080) it must answer with text; straight to
llama-server (:18080) it must answer 500 (the control). python r3_image.py KEYFILE"""
import json, sys, urllib.error, urllib.request

KEY = open(sys.argv[1]).read().strip()
PNG = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
MSGS = [{"role": "user", "content": "Read shot.png and tell me what it shows."},
        {"role": "assistant", "content": "", "tool_calls": [{"id": "t1", "type": "function",
         "function": {"name": "read", "arguments": "{\"path\": \"shot.png\"}"}}]},
        {"role": "tool", "tool_call_id": "t1", "content": [{"type": "text", "text": "Read image file [image/png]"},
                                                         {"type": "image_url", "image_url": {"url": "data:image/png;base64," + PNG}}]}]
BODY = {"messages": MSGS, "max_tokens": 120, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}


def post(port):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(BODY).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
    try:
        r = urllib.request.urlopen(req, timeout=300)
        return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


c1, r1 = post(8080)
text = ((r1.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
print(json.dumps({"via": "layer", "status": c1, "text": text[:160], "images_removed": (r1.get("layer") or {}).get("images_removed")}))
c2, r2 = post(18080)
print(json.dumps({"via": "server", "status": c2, "error": str(r2.get("error", ""))[:120]}))
