# Release bundle-20261018e (the full save of a long chain waits for idle time)

Date: 2026-10-18. Layer-only release: every `bin/` file of bundle-20261018d (engine a6d4fc698f); every other file from
`git archive` of the release commit 373e4fa (#195). What is new: after 8 deltas the full save of a conversation runs
when the layer has been idle for 30 s (`BONSAI_SLOT_CACHE_IDLE`), not after an answer; after 32 deltas
(`BONSAI_SLOT_CACHE_CHAIN_MAX`) it is forced (`docs/research/delta-saves-20261018` run 4).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | every `bin/` file byte-identical to 1018d; changed: `layer/slot_cache.py` and docs only; 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 idle | `BONSAI_8GB=1`, layer, slot folder, `BONSAI_SLOT_CACHE_CHAIN=2`, `BONSAI_SLOT_CACHE_IDLE=5`: 3 turns of a 20k conversation, then 25 s idle: the index holds a full save (depth 0) of the last state; 0 CUDA errors |
| R4 default | no cache variables: 3 turns leave at least one delta; 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.
