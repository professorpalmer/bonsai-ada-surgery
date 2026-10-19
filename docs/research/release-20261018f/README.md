# Release bundle-20261018f (save after every answer, eviction guard)

Date: 2026-10-19. Layer-only release: every `bin/` file of bundle-20261018e (engine a6d4fc698f); every other file from
`git archive` of the release commit cd2f4f0 (#198). What is new: with a delta server the layer saves after every answer
of a long conversation (a delta), and the next turn restores exactly the state after the last answer, also when
several conversations take turns (exact token test); under budget pressure a full save replaces a long chain; a save
after an answer that would evict another conversation's save used in the last 600 s (`BONSAI_SLOT_CACHE_PROTECT`) is
skipped (`docs/research/delta-saves-20261018` runs 5-9).

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | every `bin/` file byte-identical to 1018e; changed: `layer/slot_cache.py` and docs only; 0 text files with control bytes |
| R2 launcher | default, `BONSAI_8GB=1` (layer on, slot folder) and `BONSAI_TOTAL_MIB=24576`: health ok, a short greedy answer, 0 CUDA errors |
| R3 every answer | `BONSAI_8GB=1`, layer, slot folder: 3 turns of a 20k conversation: a save after each answer (slot files 1, 2, 3 after turns 1-3; turns 2-3 are deltas); 0 CUDA errors |
| R4 interleaved | two conversations that take turns (2 turns each): turns A2 and B2 each restore their own conversation's last save (cache_n at least 95 % of that conversation's previous prompt + answer); 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

## Results (`release_1018f.log`)

Zip `bonsai-bundle-win-x64-20261018f.zip`, 616684472 bytes, SHA-256
`b31859f3bc3cca670a11b58f08758096e35014e0026b07310c1fe1b17c165540`.

| Gate | Result |
|---|---|
| R1 zip | PASS: 67 entries; every `bin/` file identical to 1018e; changed `README.md`, `docs/8GB.md`, `layer/slot_cache.py`; 0 control-byte files |
| R2 launcher | PASS: default, 8 GB (layer on), 24 GB each answer; 0 CUDA errors |
| R3 every answer | PASS: slot files 1, 2, 3 after turns 1-3; the index holds the full save (21,156 tokens) and 2 deltas (28,275 / 35,404); 0 CUDA errors |
| R4 interleaved | PASS: A2 read 25 new tokens (cache_n 25,971), B2 read 24 (cache_n 25,985): each restored its own last save; 0 CUDA errors |
