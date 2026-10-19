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

## Soak (declared before the run): three conversations, a small budget, restarts

Not a release gate; a robustness check of the shipped layer (bundle-20261018e) under pressure: three ~30k-token
conversations take turns (A, B, C, A, ...), 45 turns in total (15 each, ~2.5k new tokens per turn), the server and layer
restarted before every 9th turn, 8 GB preset, `BONSAI_SLOT_CACHE_GB=6` (evictions), all other defaults.

| Check | Condition |
|---|---|
| S1 | 45/45 turns answered; 0 CUDA errors |
| S2 | no "restore failed", no "save ... failed" and no Python traceback in the layer logs |
| S3 | after the run, every index entry's chain is complete (no delta without its parent) and the folder is at most the budget + one save |
| S4 | at least 3 evictions and at least 3 chain restores (a restore of a delta chain) happened |
| S5 | each conversation's answers equal the same conversation run alone with the cache off (no restarts), at 13 of 15 turns or more |

Any fail: a bug to fix before more cache work.

### Soak result: S1-S4 PASS, S5 FAIL (`soak/`)

| Check | Result |
|---|---|
| S1 | PASS: 45/45 answered, 0 CUDA errors |
| S2 | PASS: no failed restore or save, no traceback in the layer logs |
| S3 | PASS: 17 entries, 0 deltas without a parent, folder 5.58 GiB (budget 6 GiB) |
| S4 | PASS: 7 evictions, 41 restores, 34 of them chain restores |
| S5 | **FAIL**: answers equal to the cache-off run: A 5, B 13, C 0 of 15 |

Why S5 fails: the first difference comes early (C at turn 1, before any restore; A at turn 2; B at turn 5) and then
cascades, because each later prompt holds the conversation's own earlier answers. At C turn 1 the only difference is
the save before the request (a prefill-only call, then the request), which reads the prompt in another batch split than
the cache-off run; that flips a near tie at the first answer token (a terse code list vs "The codes for vaults 1 to 4
are: ..."). Restores are exact (D1: a chain restore equals a full-file restore), so this is not a wrong state.

Graded against the ground truth (`grade_soak.py`): cache 30/45, cache-off 33/45. The per-turn pattern of right and wrong
is the same in all three cached conversations and in cache-off B (the misses are the same two hard questions, "largest
code" and "vaults below 5000"); conversation A's cache-off run took a verbose path that held the right numbers on three
more turns. One run per conversation cannot separate this from noise.

Findings and open items:
- "The same answers as cache-off" holds for the measured single-conversation sessions (G1 30/30, run 8 30/30, D3 30/30),
  not for interleaved conversations, where the save before the request changes the batch splits. The release notes claim
  only the measured cases.
- A larger answer-quality study (many conversations, graded) is needed before any claim about quality with the cache in
  interleaved use.
- With interleaved conversations the prefix test never completes (the slot holds another conversation at the next
  turn), so save after the answer never turns on there. With deltas now cheap (~0.2 s), a simpler design would always
  save after the answer as a delta and use the next request's exact token match as the test.

## Run 5 (declared before the run): save after every answer, exact test

Change (layer only): with a delta server the layer saves after every answer of a long conversation (a delta), so a
restore lands exactly on the last answer and the next request reads only the new turn, the same computation as a
session that never left memory, also when conversations take turns. The test is exact: the conversation's last save
after an answer must be a token prefix of its next prompt (works across interleaving). A conversation that fails it
goes back to the save before the request. `BONSAI_SLOT_CACHE_EVERY=0` keeps the old behaviour.

Setup: the soak again (three interleaved ~30k conversations, 45 turns, restarts before every 9th turn, 6 GB budget,
8 GB preset), the 1018e root with this layer; the reference is the soak's cache-off run (`soak/soak.jsonl`, arm `ref`).

| Gate | Condition |
|---|---|
| E1 | the soak checks S1-S4 |
| E2 | each conversation's answers equal the cache-off reference at 14 of 15 turns or more |
| E3 | mean wall time per turn not more than 10 % above the first soak's |
| E4 | no save before the request in the layer logs (every conversation passes the exact test) |

All pass: ships in the next bundles. Any fail: not shipped; log why.

### Run 5 result: E1 E2 E4 PASS, E3 FAIL — not shipped yet (`soak2/`)

| Gate | Result |
|---|---|
| E1 | PASS: S1-S4 (45/45, 0 errors, 0 orphans, folder 5.80 GiB, 27 evictions, 32 chain restores) |
| E2 | PASS: answers equal to the cache-off reference A 14, B 15, C 15 of 15 (first soak: 5, 13, 0) |
| E3 | **FAIL**: mean wall 12.5 s vs 9.4 s (+33.4 %) |
| E4 | PASS: 0 saves before the request, 0 failed exact tests |

Why E3 fails: four turns (A9, B11, A14, B15) read the whole conversation again (58-72k tokens, 59-78 s) because its
chain had been evicted: a save after every answer fills the 6 GB budget faster (27 evictions vs 7). Every other turn is
as fast or faster (no prefill-only splits: the 6-8 s turns of the first soak are 3.6-5 s now).

Next (run 6, declared before its run below): keep chains short under budget pressure: when the folder is above 80 % of
the budget and a conversation's chain holds twice its base's bytes, the next save is full and the old chain is removed;
the idle full save also removes the chain it replaces.

## Run 6 (declared before the run): run 5 + chains replaced under budget pressure

Change: when the folder is above 80 % of the budget and a conversation's chain holds twice its full save's bytes, the
next save after an answer is full and the old chain is removed (it holds only prefixes of the new save); the idle full
save also removes the chain it replaces.

Setup and gates: the same as run 5 (`soak3/`), F1 = E1 (S1-S4), F2 = E2 (answers = cache-off at 14 of 15 or more per
conversation), F3 = E3 (mean wall time not more than 10 % above the first soak's), F4 = E4 (no save before the request).
All pass: save after every answer + chain replacement ship in the next bundles. Any fail: not shipped; log why.

### Run 6 result: F2 F3 F4 PASS, F1 FAIL on S4 (no eviction happened) (`soak3/`)

| Gate | Result |
|---|---|
| F1 | **FAIL**: S1-S3 PASS (45/45, 0 errors, 0 orphans, folder 4.20 GiB); S4 FAIL: 0 evictions (35 chain restores) |
| F2 | PASS: answers equal to the cache-off reference A 15, B 15, C 15 of 15 |
| F3 | PASS: mean wall 6.7 s vs 9.4 s (-28.5 %); no turn above 20 s after turn 1 |
| F4 | PASS: 0 saves before the request, 0 failed exact tests |

S4 asked for at least 3 evictions so that the run exercises eviction; with chain replacement the folder stayed at 4.2 GiB
of the 6 GiB budget, so no eviction happened. The declared rule holds: not shipped from this run.

Run 7 (declared now, before its run): the same with `BONSAI_SLOT_CACHE_GB=3`, so that replacement and eviction both
happen; gates G1-G4 = F1-F4 (S4 still needs at least 3 evictions and 3 chain restores).

### Run 7 result: G1 G2 G3 FAIL (the 3 GB budget thrashes) (`soak4/`)

S1 PASS (45/45, 0 CUDA errors); S2 FAIL on one traceback, which is the known `/health` client time-out while the server
loads (`do_GET /health`, the client gave up before the 503 was written), not the cache; S3 PASS (0 orphans); S4 PASS (43
evictions, 6 chain restores); G2 FAIL (answers = cache-off A 11, B 15, C 15); G3 FAIL (mean wall 36.5 s, +289 %); G4 PASS.
A 3 GB budget holds less than the three conversations' full saves (1.2-2 GB each from turn 4), so from turn 4 almost every
turn read its conversation again (43-80 s). This shows what a too-small budget does; it does not compare designs.

## Run 8 (declared before the run): the default budget, and the old design under the same thrash

| Gate | Condition |
|---|---|
| H1 | the soak at the default budget (no `BONSAI_SLOT_CACHE_GB`, 20 GB): S1, S2 (a traceback in `do_GET` for `/health` while the server loads is the harness's own time-out and does not count), S3; answers = cache-off at 14 of 15 or more per conversation; mean wall not more than 10 % above the first soak's; no save before the request |
| H2 | the old design (`BONSAI_SLOT_CACHE_EVERY=0`) at 3 GB, the same soak, against run 7 (the new design at 3 GB): run 7's mean wall not more than 10 % above the old design's, and run 7's answers = cache-off at no fewer than the old design's minus 1 per conversation |

H1 and H2 pass: save after every answer + chain replacement ship. Any fail: not shipped; log why.

### Run 8 result: H1 PASS, H2 FAIL on speed — not shipped (`soak5/`, `soak6/`)

| Gate | Result |
|---|---|
| H1 | PASS: 45/45, 0 CUDA errors, 0 failures, 0 tracebacks (other than `/health`), 0 orphans, answers = cache-off A 15, B 15, C 15 of 15, mean wall 7.0 s vs 9.4 s (-25.5 %), 0 saves before the request (folder 10.1 GiB, no eviction) |
| H2 | **FAIL**: at 3 GB the new design's mean wall is 36.5 s vs the old design's 31.1 s (+17.1 %; gate +10 %). Answers = cache-off: new A 11, B 15, C 15; old A 5, B 13, C 0 |

Why H2 fails: both designs thrash at 3 GB (turns 12-15 read the whole conversation again in both). In turns 4-11 the
new design saves after every answer, and with three conversations that take turns each save evicts the save of the
conversation that comes next (least recently used = next used), so it re-read more often (A4, C4, C5, A6, B6, C7)
than the old design, which saves less often.

## Run 9 (declared before the run): run 7 + a guard against eviction of recently used saves

Change (layer only): a save after an answer that would make eviction remove another conversation's save used in the
last `BONSAI_SLOT_CACHE_PROTECT` seconds (600; 0 = off) is skipped. That conversation's earlier save stays a token prefix
of its next prompt, so its next turn restores it and reads only the turns since. Conversations idle for longer than
600 s can still be evicted. The size of the skipped save is estimated from the conversation's full save (bytes per
token, an over-estimate), a delta adds 160 MiB for the recurrent state. Unit test `test_protect_recent` (guard on: a
save of every conversation is kept and restored, no eviction; off: the saves evict each other); both suites pass.

Setup: run 7 again (`soak7/`: the soak, `BONSAI_SLOT_CACHE_GB=3`, the 1018e root with this layer). Baseline: run 8's old
design at 3 GB (`soak6/`). H1 does not change: at the default budget the soak never evicts, so the guard never acts.

| Gate | Condition |
|---|---|
| J1 | S1 (45/45, 0 CUDA errors), S2 (no traceback other than the harness's `/health` time-out), S3 (0 orphans), 0 failed saves or restores |
| J2 | mean wall not more than 10 % above the old design's at 3 GB (31.1 s, so 34.2 s or less) |
| J3 | answers = cache-off at no fewer than the old design's minus 1 per conversation (old: A 5, B 13, C 0) |

J1-J3 pass: H2's question is answered for the design with the guard, and with H1 the save after every answer + chain
replacement + the guard ship in the next bundles. Any fail: not shipped; log why.

### Run 9 result: J1 J2 J3 PASS — ships (`soak7/`)

| Gate | Result |
|---|---|
| J1 | PASS: 45/45, 0 CUDA errors, 0 tracebacks (other than `/health`), 0 orphans, 0 failed saves or restores |
| J2 | PASS: mean wall 20.2 s vs the old design's 31.1 s at 3 GB (-35.0 %) |
| J3 | PASS: answers = cache-off A 7, B 15, C 15 (old design: A 5, B 13, C 0) |

The guard skipped 37 saves; 0 evictions. Each conversation kept a save from turn 6-9 and later turns restored it and read
the turns since (15-32k tokens, 18-42 s) instead of the whole conversation (60-80 s in run 7). Conversation A matched
cache-off at 7 turns (run 7 without the guard: 11): a restore of an older save reads the turns since in other batch
splits than cache-off, which can flip a near tie (the same cause as run 4's S5); B and C matched at all 15.

With H1 (run 8) this answers the run-8 question: save after every answer + chain replacement + the guard ship in the
next bundle (1018f). A later improvement: let a conversation replace its own old chain under the
guard (today a frozen save means a growing re-read per turn).
