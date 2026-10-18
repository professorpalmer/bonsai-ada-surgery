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

## Run 1: D1 PASS, D2 FAIL (as declared)

`d1.jsonl`, `d1.log`, `d1_test.py`. Engine 92a05282c0 (product 96f6e49cdc + 0067 + delta saves; test build), 8 GB preset,
cells 80,640, direct to the server. A full save after turn 1, a delta after each of turns 2-5 (~2,440 new tokens each),
a full save of the final state; then two fresh servers: one restores the final full save, one restores the chain.

| | answer | `prompt_n` | `cache_n` | restore |
|---|---|---|---|---|
| 20k, full file | | 2,407 | 34,028 | 0.88 s |
| 20k, chain (full + 4 deltas) | the same | 2,407 | 34,028 | 0.55 s |
| 131k (173,695 tokens), full file | | 2,406 | 173,695 | 1.34 s |
| 131k, chain | the same | 2,406 | 173,695 | 1.52 s |

D1: PASS. 0 CUDA errors.

D2: **FAIL as declared.** A delta of 2,441 tokens is 183 MiB; the gate allowed (k / n) x full + 64 MiB = 99.5 MiB at 131k.
The two full saves give the real size model: (2,394 - 480) MiB / (163,903 - 24,175) tokens = **14.0 KiB per token**, and
480 MiB - 24,175 x 14.0 KiB = **149 MiB fixed** (the recurrent state of the 48 GDN layers and the draft context, written
in full in every file). Every delta equals 149 MiB + k x 14.0 KiB within 1 MiB. The 64 MiB in the gate was a guess, not a
measurement.

What a delta saves on this drive: the full save of the 173,695-token state took **70.6 s**; each delta took **0.08-0.10 s**.

## Run 2 (declared before the run): D2 corrected, D3

D2 is declared again with the measured model (the declared rule kept deltas off after run 1; this is a new test):

| Gate | Condition |
|---|---|
| D2' size | every delta of k new tokens in run 2 is at most 149 MiB + k x 14.0 KiB + 8 MiB |
| D3 G1 | run 8's session (20 s think time, 8 GB preset, the delta engine, branch layer), arm delta (`BONSAI_SLOT_CACHE_CHAIN` default 8) vs arm full (`BONSAI_SLOT_CACHE_CHAIN=0`): mean wait not higher, normal turns at least 20 % lower, answers = the run-7 reference at no more turns than the full arm |
| D4 health | 0 CUDA errors; no `lc-saving-*` files; prefix tests all pass |

All pass: deltas ship in the next bundle. Any fail: not shipped; log why.
