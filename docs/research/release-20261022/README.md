# Release bundle-20261022 (writing requests: the length is approximate, so the model does not count words)

Plan written before the runs. No engine change: every `bin/` file of bundle-20261021 (engine `810d93e5aa`). Changed
outside `docs/`: `layer/bonsai_layer.py` (#235). A writing request that names a length of 200-10,000 words or tokens,
with no hard limit, gets one sentence at its end: "About the length: an approximate length is fine. Do not count the
words one by one, in your thinking or anywhere else." Measured in
[approx-note-20261022](../approx-note-20261022/README.md) on the 8 GB preset with the published model file: writing
requests in 0.479x the time, 0 closes of the thinking budget against 8, the same quality in blind judging.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261021; every `bin/` file identical to 1021; changed outside `docs/`: `layer/bonsai_layer.py` only (plus `README.md` if it changed); 0 control-byte files; 0 broken relative links |
| R2 launcher | as release-20261021 R2 (three arms, the layer on: the draft lines, the replay line on 8 GB only, the `layer log:` line, an answer, 0 CUDA errors) |
| R3 layer | default 12 GB, layer on, through the layer: "Write a 300-word short story about a fox." answers 200 with a story and `logs\layer.log` gets the line "approximate-length note on 1 writing request(s)"; "Write a 40-line poem about rain." answers 200 and adds no such line; with `"approx_note": false` the first request adds no line; the writing and prefix-log checks of release-20261021 R3 give the same results (the story with no `interpreter_trace`, the primes with one and 3,682,913, the same prefix lines); 0 CUDA errors |
| R4 saved conversations | as release-20261021 R4 (8 GB defaults, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.
