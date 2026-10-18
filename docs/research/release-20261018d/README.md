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
