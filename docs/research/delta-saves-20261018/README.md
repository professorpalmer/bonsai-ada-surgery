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

## Run 2 result: D2', D3, D4 PASS — delta saves ship

Receipts in `run2/` (G1 session, 20 s think time, 8 GB preset; the delta arm with `BONSAI_SLOT_CACHE_CHAIN` 8, the full
arm with 0; both save after the answer).

| Gate | Result |
|---|---|
| D2' size | PASS: 13 deltas of ~8,000 tokens, 258.7-260.0 MiB each (limits 265.9-267.2 MiB) |
| D3 mean wait | PASS: 14.2 s vs 25.4 s (-44.1 %) |
| D3 normal turns | PASS: 12.6 s vs 28.9 s (-56.4 %) |
| D3 answers | PASS: both arms equal the run-7 reference on 30/30 turns |
| D4 health | PASS: 0 CUDA errors, no `lc-saving-*` files, prefix tests all pass |

Arm wall time: 1,361 s vs 1,966 s. A save after the answer took 0.17-0.2 s as a delta; the full arm's saves made the next
turn wait (turns 6, 8, 14, 20, 30: 50-89 s). With D1 (run 1) all gates pass: deltas ship in the next bundle (fork patch
0068 + the layer).

## Peer review and recheck

The review found no path to a wrong token list or a wrong target state. Fixed (fork a6d4fc698f, patch 0069):

- The draft (MTP) sidecar is always written in full and restored in full: the draft context defers the rows of the last
  verify batch, so a delta of it left a gap at each link (lower draft acceptance only).
- Deltas only for a model without SWA and without mtmd (`/props` `slot_save_delta` false, and the save refuses
  `pos_min`): a delta leaves SWA-masked cells out.
- A restore with append checks that the slot's cells end at its token count before it loads; the n_ctx check counts the
  total after the append.
- The layer never restores a delta without its chain, and restores a chain only when the server reports support.

Recheck with a6d4fc698f (`d1.jsonl`, `d1.log`; run 1's files are `run1_d1.*`): D1 passes again at 20k and 131k (the same
answer, `prompt_n` 2,407 / 2,406, `cache_n` 34,028 / 173,695 in both arms), 0 CUDA errors; each link restores the full
draft sidecar (15.0 MB).

## Run 3 (declared before the run): deltas for the save before the request

The save before the request (used when the prefix test fails, with `BONSAI_SLOT_CACHE_AFTER=0`, and by Mirai's default)
still wrote full files, and there the user waits for it. Change (layer only): that save is also a delta of the best saved
prefix when the slot starts with it.

Setup: G1 session (30 turns, 131k document, restarts before every 3rd turn, no think time), 8 GB preset, the delta engine,
`BONSAI_SLOT_CACHE_AFTER=0` in both arms; arm delta (`BONSAI_SLOT_CACHE_CHAIN` 8) vs arm full (0).

| Gate | Condition |
|---|---|
| P1 answers | the two arms give the same 30 answers (the save does not change what is computed) |
| P2 mean wait | mean `wall_s` of turns 2-30 at least 20 % lower in the delta arm |
| P3 mechanism | at least 1 delta saved before the request; no "restore failed" in the delta arm's layer log |
| P4 health | 0 CUDA errors; no `lc-saving-*` files |

All pass: ships with the next bundle (Bonsai and Mirai). Any fail: not shipped; log why.

## Run 3 result: P1-P4 PASS — deltas before the request ship

Receipts in `run3/` (`BONSAI_SLOT_CACHE_AFTER=0` in both arms, no think time).

| Gate | Result |
|---|---|
| P1 answers | PASS: 30/30 the same |
| P2 mean wait | PASS: 14.2 s vs 53.2 s (-73.4 %) |
| P3 mechanism | PASS: 13 deltas in the index; 0 restore failures |
| P4 health | PASS: 0 CUDA errors, no `lc-saving-*` files |

Arm wall time: 793 s vs 1,972 s. The save before the request took 0.23-0.24 s as a delta; the full arm's saves added
40-145 s to every second turn (the answer waits for them).

## Open item: the chain length (measured, no change yet)

Mirai MD3 (`mirai-s-serve receipts/delta/m8d`): a chain restore takes ~1.1 s per delta on the dev machine (depth 2:
2.95 s, 4: 6.69 s, 6: 9.23 s, 8: 11.42 s), because each delta carries the ~150 MiB fixed recurrent state and the full
draft sidecar. The forced full save every 8 deltas took 167 s there (a slow drive). A longer chain halves the full saves
but adds ~1 s per extra delta to every restart restore, and the balance depends on the drive. Candidates for a later
declared test: `BONSAI_SLOT_CACHE_CHAIN` 16 on slow drives (chosen from the measured speed of the last full save), or a
full save only when the layer has been idle for a while.

## Run 4 (declared before the run): the full save waits for idle time

Change (layer only): after `BONSAI_SLOT_CACHE_CHAIN` deltas (8) the full save of a conversation runs when the layer has
been idle for `BONSAI_SLOT_CACHE_IDLE` seconds (30), in a background thread under the cache lock; after
`BONSAI_SLOT_CACHE_CHAIN_MAX` deltas (32) the next save is full in any case. Before: the 9th save was full at once, after
an answer, and the next turn waited for it (Mirai MD3 turn 29: 163 s).

| Gate | Condition |
|---|---|
| I1 Bonsai | G1's first 13 turns (8 GB preset, the 1018d root + this layer, no restarts before turn 13), then 45 s idle: the layer log shows one idle full save; after a restart, turn 13 restores a chain of length 1 (the full save) and its answer equals the run-7 reference; 0 CUDA errors |
| I2 Mirai | the M8 session (Mirai 1018b root + this layer, 20 s think time, restarts, deltas in both arms) with the gates M8-1 ... M8-5 of `mirai-s-serve receipts/mirai_saa_default.md` |

I1 passes: the idle full save ships in the next bundles (Bonsai, Mirai). I2 decides `MIRAI_SLOT_CACHE_AFTER` (all pass:
on by default in the next Mirai bundle).

### Run 4, I1: FAIL as declared (the test did not reach the soft cap)

`run4/i1.*`. The G1 turns grow by ~3,990 tokens, just under the 8 GB preset's 4,096, so a save came every second turn:
after 12 turns the chain had depth 5, below the soft cap 8, so no full save was due and the 45 s idle did nothing. The
rest held: 13/13 answers equal the reference, turn 13 restored the 5-delta chain (170,671 tokens) in 1.82 s and read
7,967 tokens, 0 CUDA errors.

I1' (declared now, before its run): the same with `BONSAI_SLOT_CACHE_CHAIN=4` (soft cap 4, hard cap 16): one idle full
save in the 45 s pause; turn 13 restores a chain of length 1 and equals the reference; 0 CUDA errors.

### Run 4, I1': PASS

`run4/i1b.*` (soft cap 4). The chain reached depth 5 during the turns (the 30 s idle never came between turns, and the
hard cap is 16). In the 45 s pause the layer wrote one idle full save (174,656 tokens, 50.0 s on this drive, with no
request waiting). After the restart, turn 13 restored that full save alone (1.32 s) and read 3,982 tokens (I1: 7,967 from
the depth-5 chain). 13/13 answers equal the run-7 reference; 0 CUDA errors.
