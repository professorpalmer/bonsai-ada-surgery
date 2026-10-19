# Release bundle-20261019a (replies cut at max_tokens are no longer empty)

Date: 2026-10-19. Layer-only release: every `bin/` file of bundle-20261018f (engine `a6d4fc698f`); every other file
from `git archive` of the release commit 243bb63 (#203). What is new: through the layer, a reply that max_tokens cut
inside the layer's own run_python call came back with empty content; the layer now asks once more without its tool
(`docs/research/cut-retry-20261019`). The replay engine (bundle-20261019, staged, not published) is not in this one.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | the same entries as 1018f; every `bin/` file identical; changed: `layer/bonsai_layer.py` and docs (tests are not in the zip); 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 cut replies | `BONSAI_8GB=1` (pinned line 80,640), layer on: the six cut_live requests (max_tokens 40 / 250 at 0, 4k, 64k; stream off and on) all return text; 0 CUDA errors |
| R4 saved conversations | `BONSAI_8GB=1`, layer, slot folder: 3 turns of a 20k conversation: slot files 1, 2, 3; 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.
