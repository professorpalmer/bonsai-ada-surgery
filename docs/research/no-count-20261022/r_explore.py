"""Exploration: arm R, a note on the user message that the length is approximate. Same 3 cells as the K2 check.
python approx_x.py INNER KEYFILE"""
import json, re, sys, time, urllib.request
INNER, KEY = sys.argv[1], open(sys.argv[2]).read().strip()
P = {p["id"]: p for p in json.load(open(r"C:\Users\pwall\Projects\bonsai-saa\docs\research\no-count-20261022\prompts.json", encoding="utf-8"))}
WF = {"type": "function", "function": {"name": "write_file", "description": "Write a text file in the workspace.",
      "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}}
NOTES = {"R1": " (The length can be approximate: do not count the words.)",
         "R2": "\n\nAbout the length: an approximate length is fine. Do not count the words one by one, in your thinking or anywhere else."}
for arm, note in NOTES.items():
    for pid, seed in (("p4_blog", 5), ("p1_story", 5), ("p10_save_long", 5)):
        p = P[pid]
        body = {"messages": [{"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": p["text"] + note}], "seed": seed}
        if p["tools"]:
            body["tools"] = [WF]
        t0 = time.time()
        req = urllib.request.Request(INNER + "/v1/chat/completions", data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
        out = json.load(urllib.request.urlopen(req, timeout=1800))
        m = out["choices"][0]["message"]
        th = m.get("reasoning_content") or ""
        txt = m.get("content") or ""
        for c in m.get("tool_calls") or []:
            try:
                txt = json.loads(c["function"]["arguments"]).get("content", "")
            except Exception:  # noqa: BLE001
                pass
        numbered = len(re.findall(r"\b[A-Za-z'][\w'-]*\d{1,4}\b", th))
        print(json.dumps({"arm": arm, "prompt": pid, "seed": seed, "wall_s": round(time.time() - t0, 1),
                          "thinking_words": len(th.split()), "numbered_tokens": numbered, "words": len(txt.split()),
                          "budget_closed": "Now produce the complete answer" in th, "tool": bool(m.get("tool_calls"))}), flush=True)
