# Release bundle-20261018b (save after the answer on by default)

Date: 2026-10-18. Layer-only release: every `bin/` file of bundle-20261018 (engine c5e73e7d81); every other file from
`git archive` of the release commit ac9938f (#187). What is new: the layer saves conversations after the answer by
default (`BONSAI_SLOT_CACHE_AFTER=0` turns it off; run 8 in `docs/research/save-after-answer-20261018`).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | every `bin/` file byte-identical to 1018; changed: `README.md`, `docs/8GB.md`, `layer/slot_cache.py` only; 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 default on | `BONSAI_8GB=1`, layer, slot folder, no `BONSAI_SLOT_CACHE_AFTER`: `/layer/slot-cache` says `after: true`; after 3 turns of a 20k conversation `lc-conv.json` holds `true`; 0 CUDA errors |
| R4 off switch | the same with `BONSAI_SLOT_CACHE_AFTER=0`: `after: false` |

All pass: publish as the latest release. Any fail: no publish; log why.
