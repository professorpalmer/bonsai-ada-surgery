# Release bundle-20261018d (deltas for the save before the request)

Date: 2026-10-18. Layer-only release: every `bin/` file of bundle-20261018c (engine a6d4fc698f); every other file from
`git archive` of the release commit a6030ef (#191). What is new: the save before the request (a conversation whose
prefix test fails, or `BONSAI_SLOT_CACHE_AFTER=0`) is also a delta of the last save (run 3: mean wait -73 %, the same
answers; `docs/research/delta-saves-20261018`).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | every `bin/` file byte-identical to 1018c; changed: `layer/slot_cache.py` and docs only; 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 before | `BONSAI_8GB=1`, layer, slot folder, `BONSAI_SLOT_CACHE_AFTER=0`: 3 turns of a 20k conversation leave at least one delta; 0 CUDA errors |
| R4 default | the same with no cache variables: at least one delta; 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

## Results (`release_1018d.log`)

Zip `bonsai-bundle-win-x64-20261018d.zip`, 616,681,355 bytes, SHA-256
`63f3af825e6b24f5166ee76b6408b5dc56f1402fe8acc75e8679a6d19d035d61`.

| Gate | Result |
|---|---|
| R1 zip | PASS: 67 entries; every `bin/` file identical to 1018c (engine a6d4fc698f); changed `README.md`, `docs/8GB.md`, `layer/slot_cache.py`; 0 control-byte files |
| R2 launcher | PASS: default, 8 GB (layer on), 24 GB each answer; 0 CUDA errors |
| R3 before | PASS: `BONSAI_SLOT_CACHE_AFTER=0`: 3 turns left 2 deltas (depth 1 and 2 before the request); 0 CUDA errors |
| R4 default | PASS: no variables: 3 turns left 2 deltas; 0 CUDA errors |

## Post-release smoke: the layer's Python tool loop with the cache on

The unzipped 1018d root, 8 GB preset, layer + slot folder: 3 turns of a ~20k conversation, each asking for a computation
with `code_interpreter: true`, turn 2 streamed. All 3 answers correct (197722, 18, 9908; turn 1 used one `run_python`
round). The prefix test fails for these conversations, as expected (the tool rounds render differently in the next
turn), so they use the save before the request, which is a delta since 1018d. 0 CUDA errors. One traceback in the layer
log comes from a `/health` probe during the server load (the client timed out while the layer relayed the 503); it is not
from this release.
