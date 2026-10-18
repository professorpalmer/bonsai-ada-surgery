# Delta saves for the layer cache (#138)

Date: 2026-10-18. Hardware: RTX 4070 12 GB (the dev drive: ~1.4 GB/s for the first ~4 GB of a write, then ~30 MB/s).

## Problem

Every save writes the whole conversation state: ~5 GB for a 150k Bonsai conversation on the 8 GB preset (q3_0), ~8 GB
for Mirai (q8_0). On a drive that cannot keep its write speed, one save takes 30-190 s. Since bundle-20261018b the save
runs after the answer, but a turn sent before it ends still waits (run 8: normal turns of 34-87 s right after a save),
and the 20 GB budget holds only ~4 saves.

## Change

A save after an earlier save of the same conversation writes only the cells after it (a **delta**):

1. Engine (fork, patch 0068): the slot save takes `"pos_min": n` and writes only the attention cells with position >= n
   (the recurrent GDN state and the draft context are small and are written in full). The slot restore takes
   `"append": true`: the attention cells are added after the cells already in the slot instead of replacing them.
2. Layer: an index entry has a parent. A restore loads the chain base -> delta -> ... -> entry. A full save every 8
   deltas caps the chain. Eviction removes a chain from the end and never leaves a delta without its parent.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| D1 exact | a chain restore (base + 4 deltas) of a 20k and a 131k conversation gives the same next answer as a full-file restore, and `prompt_n` = the new tokens only |
| D2 size | a delta of k new tokens is at most (k / n) x the full file + 64 MiB (recurrent + draft state) |
| D3 G1 | run 8's session (bundle-20261018b + 0068, 20 s think time), arm delta vs arm full (run-8 after-arm settings): mean wait not higher, normal turns at least 20 % lower, answers = the reference at no more turns than the full arm |
| D4 health | 0 CUDA errors; offline tests for chains and eviction; no `lc-saving-*` files |

All pass: deltas ship in the next bundle. Any fail: not shipped; log why.
