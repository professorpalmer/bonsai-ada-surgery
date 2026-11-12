"""Expand DS1-plan.json into the concrete arm list that dspine_bench.py reads (DS1-arms.json)."""
import json
import sys

plan_path, out_path = sys.argv[1], sys.argv[2]
p = json.load(open(plan_path, encoding="utf-8"))
arms = p["arms"]
common = arms.pop("dspine_common")
out = {k: v for k, v in p.items() if k != "arms"}
out["arms"] = {"a": arms["a"], "b": arms["b"]}
for q, model_key in (("c", "c3"), ("d", "d3")):
    model = arms[model_key]["model"]
    for n in (3, 7, 15):
        args = [x.replace("<draft gguf>", model).replace("<n>", str(n)) for x in common["args"]]
        out["arms"][f"{q}{n}"] = {"what": arms[f"{q}{n}"]["what"], "model": arms["a"]["model"], "args": args, "env": dict(common["env"])}
json.dump(out, open(out_path, "w", encoding="utf-8"), indent=1)
print(list(out["arms"]))
