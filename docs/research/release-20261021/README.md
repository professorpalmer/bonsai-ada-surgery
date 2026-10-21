# Release bundle-20261021 (writing requests without the layer's run_python)

Plan written before the runs. No engine change: every `bin/` file of bundle-20261020 (engine `810d93e5aa`). Changed
outside `docs/`: `layer/bonsai_layer.py` (#227). For a chat request without client tools whose first user message asks
for prose or verse (a story, poem, chapter, essay, article, letter...), the layer no longer offers its `run_python`
tool. Measured in [story-think-20261021](../story-think-20261021/README.md) (G5): offered the tool, the model counts the
words of its text in the sandbox, up to 5 rounds; median 2.01x the wall time (a 1,500-word story: 341 s against 61 s),
with no quality gain.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261020; every `bin/` file identical to 1020; changed outside `docs/`: `layer/bonsai_layer.py` only (plus `README.md` if it changed); 0 control-byte files; 0 broken relative links |
| R2 launcher | as release-20261020 R2 (three arms, the layer on: the draft lines, the replay line on 8 GB only, the `layer log:` line, an answer, 0 CUDA errors) |
| R3 writing | default 12 GB, layer on, through the layer, no client tools: "Write a 300-word short story about a fox." answers 200 with a story and no `interpreter_trace` (the tool was not offered); "What is the sum of the first 1000 primes?" answers 200 with an `interpreter_trace` (the tool is still offered) and the right sum (3,682,913); the prefix-log requests of release-20261020 R3 give the same lines; 0 CUDA errors |
| R4 saved conversations | as release-20261020 R4 (8 GB defaults, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

## Results (2026-10-21 11:04-11:10, RTX 4070, `release_1021.log`)

Zip sha256 `27de291db6b76882...`, engine `810d93e5aa`. Scripts: `rel1021.sh`, `r3_writing.py`, `make_bundle_1021.py`
(the prefix-log requests: `../release-20261020/e2e_req.py`).

| Gate | Result |
|---|---|
| R1 zip | PASS: outside `docs/` the same entries as 1020, every `bin/` file identical; changed: `layer/bonsai_layer.py` only; 0 control-byte files; 0 broken relative links |
| R2 launcher | PASS: 8 GB `draft 1 (2 past ...)` with the replay line; 8 GB replay off `draft 1 (1 past ...)`; default `draft 2 (4 past ...)`; each: the `layer log:` line, the answer, 0 CUDA errors |
| R3 writing | PASS: the story request answered 200 with 300 words and no `interpreter_trace`; the primes request answered 200 with 1 `run_python` round and 3,682,913; the prefix-log requests gave the same lines as release-20261020 (plus one line for each of the two new conversations); 0 CUDA errors |
| R4 saved conversations | PASS: 3 turns (18.8 / 8.3 / 8.8 s); two conversations that take turns: turn 2 restored its own save (25 and 24 new tokens); 0 CUDA errors |

All gates pass: publish as the latest release.
