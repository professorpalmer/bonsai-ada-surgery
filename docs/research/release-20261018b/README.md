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

## Results (`release_1018b.log`)

Zip `bonsai-bundle-win-x64-20261018b.zip`, 616,677,712 bytes, SHA-256
`7220a7376806f39119872caa42c0a7c4a093bd3a0780c3d9e3a7e7fc4a7fb1e6`.

| Gate | Result |
|---|---|
| R1 zip | PASS: 67 entries; every `bin/` file identical to 1018 (engine c5e73e7d81); changed `README.md`, `docs/8GB.md`, `layer/slot_cache.py`; 0 control-byte files |
| R2 launcher | PASS: default (q4_0), 8 GB (q3_0, layer on), 24 GB (q8_0) each answer; 0 CUDA errors |
| R3 default on | PASS: `{"after": true}` with no variable set; `lc-conv.json` `true` after 3 turns; 0 CUDA errors |
| R4 off switch | PASS: `BONSAI_SLOT_CACHE_AFTER=0` gives `{"after": false}` |
