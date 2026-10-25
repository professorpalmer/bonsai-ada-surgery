# Release bundle-20261025 (the layer reports what it changed, and can show what a client changed)

Plan written before the runs. No engine change: every `bin/` file of bundle-20261022 (engine `810d93e5aa`). Changed
outside `docs/`: `layer/bonsai_layer.py` only.

- #238: a non-streamed answer that the layer forwards now carries `"layer": {...}` with the changes the layer made to
  the request (for example `approx_notes`, `images_removed`), as the interpreter path already does.
- #241: `BONSAI_LAYER_PREFIX_DIFF=1` (opt-in) adds, to each prefix-change line in `logs\layer.log`, an excerpt of the
  first changed text, before and now. Issue #7: a client rewrote its developer message in the middle of a 230k session,
  and the server read 221,714 tokens again (438 s); the log said which message changed, not how.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261022; every `bin/` file identical to 1022; changed outside `docs/`: `layer/bonsai_layer.py` only (plus `README.md` if it changed); 0 control-byte files; 0 broken relative links |
| R2 launcher | as release-20261022 R2 (three arms, the layer on: the draft lines, the replay line on 8 GB only, the `layer log:` line, an answer, 0 CUDA errors) |
| R3 layer | default 12 GB, layer on, `BONSAI_LAYER_PREFIX_DIFF=1`, through the layer: the release-20261022 R3 checks give the same results (the note line for the 300-word story and none for the poem or with `"approx_note": false`; the story with no `interpreter_trace`; the primes with one and 3,682,913; the same prefix-change lines); and new: the 300-word story's answer has `layer.approx_notes` = 1, the poem's answer has no `layer` object, and each prefix-change line for an edited message or a changed tool list is followed by a "first change in" excerpt; 0 CUDA errors |
| R4 saved conversations | as release-20261022 R4 (8 GB defaults, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.
