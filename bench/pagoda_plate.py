"""Replay of Killy's plate 037P (voxel pagoda) against a running server, rendered headless.

Prompt as printed on the plate ("..." marks text the plate elides). The plate ran in a sealed headless
Chrome with three r160 vendored and no network; this replay loads three from unpkg as the prompt asks and
screenshots each page with headless Edge/Chrome after RENDER_WAIT_MS.

--repair N adds a render-check-repair loop: each page is run headless with a probe that records console
errors and inspects the Three.js scene (mesh count, voxels not connected to the ground-standing structure,
whether the structure is in the camera's view). When the probe finds a problem, its report goes back to the
model as a follow-up turn ("I ran your page; here is what happened") and the model returns a fixed page.
The probe reports facts about the running page only; it never tells the model how to fix anything.

  python bench/pagoda_plate.py --key-file artifacts/api_key.txt --arms medium,off
  python bench/pagoda_plate.py --arms medium,high,off --samples 3 --repair 3
"""
from __future__ import annotations

import argparse
import html as htmllib
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request

PROMPT = (
    "Build a voxel-art 3D pagoda as a single self-contained HTML file using Three.js loaded from unpkg. "
    "Use only cubes (BoxGeometry) as the voxels. The pagoda has five tiers with stacked roofs, a base, and a "
    "spire on top. Add a ground plane, lighting, and a camera that slowly orbits the pagoda. Return only the HTML."
)
BROWSERS = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
]

# Installed first in <head>: collects errors, finds the scene (global THREE or the module shim below), and after
# the page has rendered for a while writes a JSON report into <script id="__probe_out">.
PROBE_HEAD = r"""<script>
(function(){
  var P = window.__probe = {errors: [], frames: 0};
  function note(m){ if (P.errors.length < 8 && P.errors.indexOf(m) < 0) P.errors.push(String(m).slice(0, 300)); }
  window.addEventListener('error', function(e){
    var t = e.target, u = t && t !== window && (t.src || t.href);
    if (u) note('failed to load ' + u);
    else if (t && t.tagName === 'SCRIPT') note('a <script type="' + (t.type || 'text/javascript') + '"> element failed to load or resolve one of its imports');
    else note((e.message || 'error') + (e.lineno ? ' (line ' + e.lineno + ')' : '')); }, true);
  window.addEventListener('unhandledrejection', function(e){ note('unhandled rejection: ' + (e.reason && e.reason.message || e.reason)); });
  var ce = console.error; console.error = function(){ note([].slice.call(arguments).join(' ')); return ce.apply(console, arguments); };
  // three defines render() per instance, so wrap the constructor (a module shim or the global THREE setter).
  window.__probeWrap = function(T){
    P.T = T; var R = T.WebGLRenderer;
    return class extends R { constructor(){ super(...arguments); var r = this.render, self = this;
      this.render = function(s, c){ P.scene = s; P.camera = c; P.frames++; return r.apply(self, arguments); }; } };
  };
  var G;
  Object.defineProperty(window, 'THREE', {configurable: true, get: function(){ return G; }, set: function(v){
    G = v; var W;
    Object.defineProperty(v, 'WebGLRenderer', {configurable: true, enumerable: true, get: function(){ return W; },
      set: function(R){ W = R; W = window.__probeWrap(v); }});
  }});
  function analyse(){
    try { performance.getEntriesByType('resource').forEach(function(r){
      if (r.responseStatus >= 400) note('HTTP ' + r.responseStatus + ' fetching ' + r.name); }); } catch (e) {}
    var out = {errors: P.errors, frames: P.frames};
    try {
      if (!P.scene) { out.scene = null; }
      else {
        var T = P.T, boxes = [];
        P.scene.updateMatrixWorld(true);
        P.scene.traverse(function(o){
          if (!o.isMesh || !o.visible) return;
          var b = new T.Box3().setFromObject(o);
          if (!isFinite(b.min.x) || b.isEmpty()) return;
          boxes.push(b);
        });
        out.meshes = boxes.length;
        if (boxes.length) {
          // Ground: the largest-footprint flat mesh touching the lowest level.
          var gi = -1, ga = 0;
          boxes.forEach(function(b, i){ var s = b.getSize(new T.Vector3()); var a = s.x * s.z;
            if (s.y < 0.2 * Math.max(s.x, s.z) && a > ga) { ga = a; gi = i; } });
          var struct = boxes.map(function(b, i){ return i; }).filter(function(i){ return i !== gi; });
          var ground = gi >= 0 ? boxes[gi] : null;
          // Connectivity: boxes touch when they overlap or meet within a small tolerance.
          var sizes = struct.map(function(i){ var s = boxes[i].getSize(new T.Vector3()); return Math.min(s.x, s.y, s.z); }).sort(function(a, b){ return a - b; });
          var eps = Math.max(1e-3, 0.05 * (sizes[Math.floor(sizes.length / 2)] || 1));
          function touch(a, b){ return a.min.x <= b.max.x + eps && b.min.x <= a.max.x + eps && a.min.y <= b.max.y + eps && b.min.y <= a.max.y + eps && a.min.z <= b.max.z + eps && b.min.z <= a.max.z + eps; }
          var n = struct.length, seen = new Array(n).fill(false), q = [];
          var low = Infinity; struct.forEach(function(i){ low = Math.min(low, boxes[i].min.y); });
          struct.forEach(function(i, k){ var b = boxes[i]; if ((ground && touch(b, ground)) || b.min.y <= low + eps) { seen[k] = true; q.push(k); } });
          var limit = Math.min(n, 6000);
          while (q.length) { var k = q.pop(), bk = boxes[struct[k]];
            for (var j = 0; j < limit; j++) if (!seen[j] && touch(bk, boxes[struct[j]])) { seen[j] = true; q.push(j); } }
          var floating = [], all = new T.Box3();
          struct.forEach(function(i, k){ all.union(boxes[i]); if (!seen[k]) floating.push(boxes[i]); });
          out.structure = {count: n, size: all.getSize(new T.Vector3()).toArray().map(function(v){ return +v.toFixed(2); }),
                           min_y: +all.min.y.toFixed(2), max_y: +all.max.y.toFixed(2)};
          out.floating = floating.length;
          if (floating.length) {
            // Summarise floating pieces by height band, and the vertical gap under each band.
            // gap_below: distance down to the nearest geometry directly underneath (overlapping in x and z).
            var bands = {};
            floating.forEach(function(f){ var y = Math.round(f.min.y * 2) / 2, below = ground ? ground.max.y : -Infinity;
              struct.forEach(function(i){ var b = boxes[i];
                if (b !== f && b.max.y <= f.min.y + eps && b.min.x < f.max.x && f.min.x < b.max.x && b.min.z < f.max.z && f.min.z < b.max.z)
                  below = Math.max(below, b.max.y); });
              var g = isFinite(below) ? f.min.y - below : null, e = bands[y] || (bands[y] = {n: 0, gap: 0});
              e.n++; if (g !== null) e.gap = Math.max(e.gap, g); });
            out.floating_bands = Object.keys(bands).map(Number).sort(function(a, b){ return a - b; }).slice(0, 10).map(function(y){
              return {bottom_y: y, pieces: bands[y].n, gap_below: +bands[y].gap.toFixed(2)};
            });
          }
          if (P.camera && n) {
            var c = all.getCenter(new T.Vector3()).project(P.camera);
            out.center_on_screen = Math.abs(c.x) <= 1 && Math.abs(c.y) <= 1 && c.z <= 1;
          }
        }
      }
    } catch (e) { out.probe_error = String(e); }
    var s = document.createElement('script'); s.type = 'application/json'; s.id = '__probe_out';
    s.textContent = JSON.stringify(out); document.documentElement.appendChild(s);
  }
  setTimeout(analyse, __WAIT__);
})();
</script>
"""

# Module pages: the import of three.module.js is routed through this shim so the probe can see the renderer.
SHIM = """import * as T from "{url}";
export * from "{url}";
export const WebGLRenderer = window.__probeWrap ? window.__probeWrap(T) : T.WebGLRenderer;
"""
MODULE_URL = re.compile(r"https://(?:unpkg\.com|cdn\.jsdelivr\.net/npm)/three@([\w.\-]+)/build/three\.module(?:\.min)?\.js")


def chat(base: str, key: str, arm: str, messages: list, max_tokens: int, temperature: float | None) -> dict:
    kwargs = {"enable_thinking": arm != "off", "reasoning_effort": arm if arm != "off" else "medium"}
    body = {"model": "bonsai-2-27b", "messages": messages, "max_tokens": max_tokens, "chat_template_kwargs": kwargs}
    if temperature is not None:
        body["temperature"] = temperature
    req = urllib.request.Request(base.rstrip("/") + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "Authorization": "Bearer " + key})
    t0 = time.time()
    out = json.load(urllib.request.urlopen(req, timeout=3600))
    msg = out["choices"][0]["message"]
    return {"content": msg.get("content") or "", "finish": out["choices"][0].get("finish_reason"),
            "tokens": (out.get("usage") or {}).get("completion_tokens"), "seconds": round(time.time() - t0, 1)}


def extract_html(text: str) -> str:
    m = re.search(r"```(?:html)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE)
    html = m.group(1) if m else text
    return html.strip()


def browser() -> str | None:
    return next((b for b in BROWSERS if os.path.exists(b)), None)


def headless(args: list, wait_ms: int, target: str) -> subprocess.CompletedProcess:
    cmd = [browser(), "--headless=new", "--disable-gpu-sandbox", "--use-angle=swiftshader", "--hide-scrollbars",
           "--allow-file-access-from-files", "--window-size=800,800", f"--virtual-time-budget={wait_ms}", *args,
           "file:///" + target.replace("\\", "/")]
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)


def render(html_path: str, png_path: str, wait_ms: int) -> str:
    if not browser():
        return "no headless browser found"
    r = headless([f"--screenshot={png_path}"], wait_ms, html_path)
    return "ok" if os.path.exists(png_path) else (r.stderr or r.stdout)[-300:]


def dead_urls(html: str) -> list[str]:
    """HTTP status of every external URL the page references (script src, import map, import specifiers)."""
    bad = []
    for u in sorted(set(re.findall(r"""["'](https?://[^"'\s]+)["']""", html))):
        try:
            req = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
            urllib.request.urlopen(req, timeout=20).close()
        except urllib.error.HTTPError as e:
            bad.append(f"HTTP {e.code} fetching {u}")
        except Exception as e:  # network trouble is not the page's fault; report it plainly
            bad.append(f"could not fetch {u}: {e}")
    return bad


def probe(html: str, work: str, wait_ms: int) -> dict:
    """Run the page with the probe installed and return its JSON report."""
    os.makedirs(work, exist_ok=True)
    shims = {}
    def to_shim(m: re.Match) -> str:
        name = f"_probe_three_{m.group(1)}.js"
        shims[name] = SHIM.format(url=m.group(0))
        return "./" + name
    page = MODULE_URL.sub(to_shim, html)
    for name, src in shims.items():
        open(os.path.join(work, name), "w", encoding="utf-8").write(src)
    head = PROBE_HEAD.replace("__WAIT__", str(max(1000, wait_ms - 1500)))
    page = re.sub(r"(<head[^>]*>)", lambda m: m.group(1) + head, page, count=1, flags=re.IGNORECASE) \
        if re.search(r"<head[^>]*>", page, re.IGNORECASE) else head + page
    path = os.path.abspath(os.path.join(work, "_probe.html"))
    open(path, "w", encoding="utf-8").write(page)
    shift = head.count("\n")
    r = headless(["--dump-dom"], wait_ms, path)
    m = re.search(r'<script type="application/json" id="__probe_out">([\s\S]*?)</script>', r.stdout)
    if not m:
        return {"probe_error": "page produced no report (it may have hung or failed to load)"}
    rep = json.loads(htmllib.unescape(m.group(1)))
    rep["dead_urls"] = dead_urls(html)
    rep["errors"] = [re.sub(r"\(line (\d+)\)", lambda k: f"(line {max(1, int(k.group(1)) - shift)})", e)
                     for e in rep.get("errors") or []]
    return rep


def problems(rep: dict) -> list[str]:
    """Turn a probe report into plain observations. Empty list = nothing wrong was observed."""
    out = []
    for e in rep.get("errors") or []:
        out.append(f"Console error: {e}")
    for u in rep.get("dead_urls") or []:
        out.append(u)
    if rep.get("probe_error"):
        out.append(rep["probe_error"])
    if "scene" in rep and rep["scene"] is None and not rep.get("probe_error"):
        out.append("No Three.js scene was ever rendered (renderer.render was never called).")
    elif rep.get("meshes") == 0:
        out.append("The scene rendered but contains no visible meshes.")
    if rep.get("floating"):
        st = rep.get("structure") or {}
        bands = "; ".join(f"{b['pieces']} piece(s) with bottom at y={b['bottom_y']}"
                          + (f", up to {b['gap_below']} above whatever is under it" if b.get("gap_below") else "")
                          for b in rep.get("floating_bands") or [])
        out.append(f"{rep['floating']} of {st.get('count')} voxels do not touch the structure that stands on the "
                   f"ground; they hang in the air. Floating pieces: {bands}.")
    if rep.get("center_on_screen") is False:
        out.append("The center of the structure is outside the camera's view.")
    return out


def feedback(obs: list[str]) -> str:
    return ("I ran your page in headless Chrome and inspected the rendered scene. What I observed:\n- "
            + "\n- ".join(obs) + "\n\nFix these problems and return the complete corrected HTML file only.")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8080")
    ap.add_argument("--key-file", default="artifacts/api_key.txt")
    ap.add_argument("--arms", default="medium,off", help="off, low, medium, high")
    ap.add_argument("--samples", type=int, default=1)
    ap.add_argument("--repair", type=int, default=0, help="max render-check-repair rounds per sample")
    ap.add_argument("--temperature", type=float, default=None)
    ap.add_argument("--max-tokens", type=int, default=24576)
    ap.add_argument("--wait-ms", type=int, default=6000)
    ap.add_argument("--out", default=os.path.join("artifacts", "eval", "pagoda"))
    a = ap.parse_args()
    key = open(a.key_file, encoding="utf-8").read().strip()
    os.makedirs(a.out, exist_ok=True)
    log = open(os.path.join(a.out, "log.jsonl"), "a", encoding="utf-8")
    for arm in a.arms.split(","):
        for s in range(a.samples):
            messages = [{"role": "user", "content": PROMPT}]
            for rnd in range(a.repair + 1):
                g = chat(a.base, key, arm, messages, a.max_tokens, a.temperature)
                html = extract_html(g["content"])
                tag = f"{arm}" + (f"_s{s}" if a.samples > 1 else "") + (f"_r{rnd}" if a.repair else "")
                hp = os.path.abspath(os.path.join(a.out, f"pagoda_{tag}.html"))
                open(hp, "w", encoding="utf-8").write(html)
                pp = os.path.abspath(os.path.join(a.out, f"pagoda_{tag}.png"))
                status = render(hp, pp, a.wait_ms) if html else "empty answer"
                rep = probe(html, os.path.join(a.out, "_probe"), a.wait_ms) if html else {"probe_error": "empty answer"}
                obs = problems(rep)
                print(f"{tag:14} finish={g['finish']} tokens={g['tokens']} {g['seconds']}s html={len(html)} "
                      f"render={status} meshes={rep.get('meshes')} floating={rep.get('floating')} "
                      f"errors={len(rep.get('errors') or [])}", flush=True)
                log.write(json.dumps({"tag": tag, "arm": arm, "sample": s, "round": rnd, "finish": g["finish"],
                                      "tokens": g["tokens"], "seconds": g["seconds"], "probe": rep,
                                      "observations": obs}) + "\n")
                log.flush()
                if not obs or rnd == a.repair:
                    break
                messages += [{"role": "assistant", "content": g["content"]}, {"role": "user", "content": feedback(obs)}]


if __name__ == "__main__":
    main()
