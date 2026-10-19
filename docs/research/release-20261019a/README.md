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

## Results (`release_1019a.log`)

Zip `bonsai-bundle-win-x64-20261019a.zip`, 616685079 bytes, SHA-256 `206e1e9d0b47e978adf08e7e97237df1b9d957ae998fc400a4865f1dfab5fa83`.

| Gate | Result |
|---|---|
| R1 zip | PASS: 67 entries; every `bin/` file identical to 1018f; changed `README.md`, `docs/8GB.md`, `layer/bonsai_layer.py` (the launcher kept as in 1018f); 0 control-byte files |
| R2 launcher | PASS: default, 8 GB (layer on), 24 GB each answer; 0 CUDA errors |
| R3 cut replies | PASS: 6 of 6 return text (245 / 1,018-1,177 characters); the 4k and 64k document requests took the retry (`cut_retry`, 500 completion tokens); 0 CUDA errors |
| R4 saved conversations | PASS: slot files 1, 2, 3 (full save + 2 deltas); 0 CUDA errors |
