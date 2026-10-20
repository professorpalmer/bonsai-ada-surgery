# Events, 2026-10-17 to 2026-10-19 (range p200-p219)

Notebook entries in this range that are not experiments: PRs, releases, issue threads, decisions, incidents, a research
pass and lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-17 22:30 CDT Kernel
session P189 plan (4070) ..." to the entry "2026-10-19 18:39 CDT Cary: "do the records, then wait for the bundle" ...",
receipts/queue.log, receipts/build_ahead.log, the receipts named below, the queue files' write times, the server logs
(`logs/`, not in this repo) where a record says so, the thread of issue #138 from 03:51:10Z (2026-10-18) to 22:46:41Z
(2026-10-19), the PRs and releases of this repo, and the fork branches `r6-0070`, `kv-fake2` and `turing-mmq`. Numbering
continues from `events-p183-p188.md` (E88-E95). Times with "Z" are UTC (GitHub); "CDT" and other times are rig local time
(UTC-5). The GitHub posts of all sessions use the same account; "4070", "2060", "kernel session" and "release session"
name the session.

- [E96 Records PR #177 and the corrections post](#e96-records-pr-177-and-the-corrections-post)
- [E97 The kernel session closes the T5 window lead, and the jump to P200](#e97-the-kernel-session-closes-the-t5-window-lead-and-the-jump-to-p200)
- [E98 G1 on two cards and the 8 GB save step (PR #182)](#e98-g1-on-two-cards-and-the-8-gb-save-step-pr-182)
- [E99 Save after the answer: from opt-in to the default, and my P204 mistake](#e99-save-after-the-answer-from-opt-in-to-the-default-and-my-p204-mistake)
- [E100 Bundles 20261018 to 20261018f, the post-zip checks and the serve folders](#e100-bundles-20261018-to-20261018f-the-post-zip-checks-and-the-serve-folders)
- [E101 Clock tuning on the 2060: slot 3 as an optional serve step](#e101-clock-tuning-on-the-2060-slot-3-as-an-optional-serve-step)
- [E102 Replay rollback and draft 2 / 2: from the R6 groundwork to bundle-20261019b](#e102-replay-rollback-and-draft-2--2-from-the-r6-groundwork-to-bundle-20261019b)
- [E103 Research pass 2 and the sub-3-bit KV probe](#e103-research-pass-2-and-the-sub-3-bit-kv-probe)
- [E104 Queue incidents: two first tries that failed at their start](#e104-queue-incidents-two-first-tries-that-failed-at-their-start)
- [E105 GPU time in this range](#e105-gpu-time-in-this-range)
- [E106 Corrections in this range](#e106-corrections-in-this-range)
- [E107 Lessons recorded in this range](#e107-lessons-recorded-in-this-range)
- Continued in [`events-p220-p223.md`](events-p220-p223.md) (E108-E116)

## E96 Records PR #177 and the corrections post

| | |
| --- | --- |
| Date | PR #177 "research: depth-8gb P183-P188 records" opened 03:50:21Z, merged 03:51:08Z (d065a60); the corrections post 03:51:10Z (comment 6245364532); notebook "22:51 CDT Records PR #177 (P183-P188) merged (d065a60); CORRECTIONS posted on #138" |
| What | "**Corrections to my 2060 T5 posts, from the records review (PR #177, merged).** The T5 hold does not change: it rests on the 4070's controls." P183 was not a rounding-only null arm (P170 / P188 ran sparse auto, P183 `BONSAI_SPARSE=0`): "My posts at 02:28Z and 03:22Z ... are wrong. Please disregard them." Against the matched dense run P183, P187 has 2 wrong prose answers (22, 23), "So it does not pass the clause on the 2060 either." Smaller items: the weights part is ~63-64 % of a T5 read; P185's "162 OK" is log interleaving; P184's line was 86,528 |
| Lesson (post) | "the window-off reference must use the same bins and the same `BONSAI_SPARSE`, in the same block" |
| Links | PR #177; `events-p183-p188.md` E94 |

## E97 The kernel session closes the T5 window lead, and the jump to P200

| time (Z) | session | comment | what |
| --- | --- | --- | --- |
| 04:42:37 | kernel | 6245757050 | Its "P189" result: no candidate. Window 32k 1.77x, lost 3; 64k 1.44x, lost 2; 32k + sink 8k lost 5. "the windowed read is deterministic too" (48/48 = #174). The declared check on the mean drift fails (one null item sets the mean); "a next gate must declare a robust statistic (median or p90) before the data" |
| 04:44:37 | kernel | 6245772229 | Its "P190" plan: every N-th far 256-block visible (`stride=N`, fork branch `t5-stride`), gated on the median and p90 drift |
| 05:54:13 | kernel | 6246295014 | Its "P191" plan: stride 8 with a +log(8) bias, f16 mask (quality only) |
| 06:31:02 | kernel | 6246585161 | "**P190 and P191 results: lead 2 closes. T5 stays held.**" Stride 8: 1.44x, lost 1 (packed) or 3 (f16, rounding only); the bias "does not help, it hurts" (median 2.2x). "No setting reaches the null band. The kernel session stops work on the window." |

- Notebook 01:33 CDT: "Future window rounds must gate on drift median / p90 vs a null arm, declared first. Cold read
  status: exact floor ~8.6 min at 245k on the 2060; the shipped answer stays "read once (read ahead) + restore in
  seconds"."
- Numbering: notebook 22:30 CDT "the kernel session uses P188 / P189 for 4070 runs; my next 2060 experiment is P190";
  00:55 CDT "the kernel session now uses P188-P191; my next 2060 experiment is P200 (unique records)". So P189-P199 do
  not exist in this series. The kernel session's runs are not 2060 records; they are cited by comment.
- Nothing was asked of the 2060 in this part (notebook 23:44 and 00:55 CDT). The GPU ran fillers from 22:21:50 to
  05:13:55 (E105).

## E98 G1 on two cards and the 8 GB save step (PR #182)

| time (Z) | session | comment / PR | what |
| --- | --- | --- | --- |
| 10:02:48 | release | 6248539701 | Plan G1 (4070): `BONSAI_SLOT_CACHE_GROW` 8192 vs 4096 in P164's session; gates restart -25 %, normal <= +10 %, total lower, answers >= 28/30. "the 2060 agent suggested 4096" (the P164 record) |
| 10:13:56 | 2060 | - | P200 starts (05:13:56 CDT; the queue file 05:13:53) |
| 10:42:59 | release | 6248882341 | G1 result (4070): 4096 is worse: 1,124 vs 748 s (+50 %); normal turns 30.0 vs 11.5 s; "The default stays 8192." |
| 10:44:24 | 2060 | 6248894588 | "**P200 runs the same A/B on the 2060 now**"; "I do not expect a change unless the numbers clearly say so" |
| 11:32:47 | 2060 | 6249409712 | P200: 4096 passes all four gates (restart -48.5 %, normal +8.8 %, total -18.7 %, 30/30). Proposal: the 8 GB preset sets 4096 when unset |
| 11:38:50 | release | 6249463524 | "**P200: adopted.** PR #182 ... The real 8 GB card is the target of this preset, so its result decides over the 4070's G1." |
| 11:40:02 | release | PR #182 (7031386) | merged; shipped in bundle-20261018 (14:10:29Z) |

- Why the cards differ: on the 2060 a re-read of ~12k tokens takes 76-117 s and a save 4-7.5 s (P200 layer logs). The
  4070 (10:42:59Z): "On this card each extra save (a prefill-only call + a ~2-4 GB write) costs more than the shorter
  re-read after a restart saves".

## E99 Save after the answer: from opt-in to the default, and my P204 mistake

| time (Z) | session | comment / PR | what |
| --- | --- | --- | --- |
| 11:38:50 | release | 6249463524 | Plan: branch `cache/save-after-answer`, `BONSAI_SLOT_CACHE_AFTER=1`, gates A-F; "If it passes on the 4070, a 2060 run of the same A/B would be the real 8 GB check (on top of GROW 4096)." |
| 14:01:15 | release | PR #184 | merged (opt-in) |
| 14:11:33 | release | 6250909875 | bundle-20261018 published; 4070 run 5: A, B (-56.1 %), D, E, F pass, **C FAIL (+94.2 %)**: the next turn waits for the post-answer save; patch 0067 found on the way. "**Request for the 2060 (P201):** the same A/B on `bundle-20261018` with the defaults (GROW 4096 on 8 GB)" |
| 14:15:35 | 2060 | 6250951773 | Queued as P204 ("My P201 is the power test, so this record keeps its own number") |
| 15:38:26 | release | 6251785976 | 4070 run 6 (20 s think time): W1 fails (29/30, turn 5 near tie); stays opt-in (#186) |
| 15:51:11 | 2060 | 6251915503 | "**P204 ... a valid A/B, but at GROW 8192, not the 8 GB default 4096. My mistake.**" B -6.2 % FAIL; P205 runs |
| 17:03:15 | 2060 | 6252653262 | P205 (GROW 4096): A, C, D, E, F PASS; B -5.4 % FAIL; "no reason to change the opt-in status, and no harm if a user turns it on" |
| 17:04:37 | release | release bundle-20261018b | published |
| 17:05:19 | release | 6252674974 | "**Decision: save after the answer is the default from bundle-20261018b**". Run 7 (cache off, no restarts) is the reference; run 6's after arm equals it 30/30, every save-before arm differs at turn 5; run 8 passes all gates. "P205 ... no harm" |

- My mistake (P204): the layer runs outside the launcher, so it did not get the launcher's 8 GB `BONSAI_SLOT_CACHE_GROW`
  default; the script also unset it. Both arms ran at 8192. Cost: P204's 1.42 h of GPU gave a valid A/B for the wrong
  recipe; P205 (1.19 h) ran the right one. Lesson: export the launcher's layer variables for an external layer and read
  the save spacing in its log (E107).

## E100 Bundles 20261018 to 20261018f, the post-zip checks and the serve folders

| bundle | published (Z) | what (release notes, #138) | zip SHA-256 (notebook) | 2060 check | serve folder (notebook) |
| --- | --- | --- | --- | --- | --- |
| 20261018 | 10-18 14:10:29 | engine c5e73e7d81 = product + 0067 (a draft stops at the end of the answer); #182 GROW 4096 on 8 GB; #184 save after the answer opt-in | f8347f4e... (616,677,417 B) | P206 PASS (not asked) | - |
| 20261018b | 10-18 17:04:37 | save after the answer by default (layer only, bins = 1018) | 7220a737... | covered by P206 ("16/16 bins = 1018") | serve-1018b |
| 20261018c | 10-18 20:48:30 | delta saves, engine a6d4fc698f (patches 0068-0069) | 6111693d... | P209 PASS (asked, 6254974925) | serve-1018c |
| 20261018d | 10-18 23:28:07 | deltas for the save before the request too (layer only, bins = 18c) | 63f3af82... | P210 PASS (optional, 6256728882) | serve-1018d |
| 20261018e | 10-19 01:19:26 | the full save after 8 deltas waits for 30 s idle (`BONSAI_SLOT_CACHE_IDLE`), forced after 32 (layer only) | ebc7c4da... | none ("No check needed on the 2060", 6257750159) | serve-1018e |
| 20261018f | 10-19 04:44:08 | save after every answer as a delta, exact restore to the last answer (layer, PR #198) | b31859f3... | P211 + P212 PASS (not asked) | serve-1018f |
| 20261019a | 10-19 12:20:38 | replies cut at max_tokens are no longer empty (PR #203) | - | none; not in the notebook | - |
| 20261019b | 10-19 22:15:39 | 8 GB defaults to replay rollback + draft 2 / tail 2; engine 810d93e5aa (0070 + 0071) | d5a53c2b2ad238e2... (#138 22:16:16Z) | the formal R6: not run at the time of writing | - |

- Each serve folder was "built from the ... zip (0 files differ, same key)" for Cary to serve. The serve notes
  (`SERVE_FOR_MAC.md`) are private (they hold a LAN address) and are not in this repo.
- The 2060 posts on the chain length (00:14:27Z): "on this card a full save is ~4-5 s and a chain restore ~2.4-3.2 s at
  depth <= 3, so the default 8 costs little here either way."

## E101 Clock tuning on the 2060: slot 3 as an optional serve step

| run | slot | cold 64k | cold 240k | SM median | temp max | result |
| --- | --- | --- | --- | --- | --- | --- |
| P201 | 1: 215 W | +1.8 % | 1,400.3 vs 1,418.3 s (+1.3 %) | 1,875 (stock 1,845-1,875) | 79 C | gates PASS; not worth it |
| P202 | 3: 215 W + core +100 | +5.9 % | 1,348.4 vs 1,416.8 s (+5.1 %) | 1,965 | 79 C | PASS |
| P203 | 3, 30-turn session | - | session 2,173 vs 2,266 s | max 2,025 | 77 C | PASS, 30/30 answers |
| P207 | 4: 215 W + core +150 | +8.3 % | 1,937.5 s (no stock read in block) | 2,025-2,040 | 80 C | gates PASS; long read slow |
| P208 | 4, again | - | 1,574.3 vs 1,505.8 s stock in block | 2,025 | 79 C | slot 4 out |

| | |
| --- | --- |
| Posts | 13:43:39Z (P201 / P202, comment 6250633645); 14:26:07Z (P203, comment 6251057162); 21:18:46Z (P207 / P208, comment 6255268346) |
| Decision | Slot 3 is an optional step in the serve notes ("BonsaiAB_P3 before the start, P5 after the stop"); "It is not a launcher default, because other 2060s may not hold +100." Slot 4 is out: it falls behind past ~125k in both runs |
| Method | Every server start in every job of this range first applies slot 3 and then slot 5 with no server up (slot 5 alone does nothing when it is already active), so each run starts on stock clocks. An OC arm applies its slot (slot 5, then the OC slot) between servers only (P39c). An EXIT trap stops the server and applies stock whatever happens. The arm is void unless `power.limit` reads the planned value (one retry), and for a core offset the SM median must be +60 MHz over stock. The profile file is staged by `afterburner/make_staged.py` and installed by the `BonsaiAB_Install` task inside the job, with no server up (P201) |
| Noise | Stock 240k reads: 1,416.8 s (P202), 1,418.3 s (P201), 1,505.8 s (P208): the deep part past the VRAM line varies ~6 % from run to run on this rig |

## E102 Replay rollback and draft 2 / 2: from the R6 groundwork to bundle-20261019b

| time (Z) | session | comment / PR | what |
| --- | --- | --- | --- |
| 08:11:09 | release | PR #201 (44fd1c4) | patch 0070 + launcher `BONSAI_RS_REPLAY=1` (opt-in): one recurrent plane in place of one per draft token, -142 MiB on 8 GB; 4070 decode +10.3 % at 128k; "Default-on waits for R6 on the RTX 2060." |
| 08:45:11 | release | PR #202 (40244cb) | release-20261019 records: the replay bundle staged, not published, because the R3 VRAM-line check "cannot run on the RTX 4070 ... until the check runs on the RTX 2060" |
| 11:13 | 2060 | - | Notebook 06:13 CDT: Cary "keep grinding, check back in a few hrs"; the R6 groundwork plan (no product-0070 branch: `git am` of patches/0070 onto product-0069 -> r6-0070 64b85111e) |
| 12:42:50 | 2060 | 6267476922 | P213: identity at a pinned line, +10,496 cells, decode at 128k +13.9 %, a soak with 0 errors |
| 13:21:13 | 2060 | 6268228843 | P214: +2.4 % at 200k; "the 2060 data supports default-on for the 8 GB preset" |
| 14:23:11 | 2060 | 6269525273 | P215: 2 / 2 +21.8 % at 128k for 512 cells; proposed for the 0070 release with a quality gate |
| 14:28:25 | release | 6269639500 | The 4070 runs adaptive MTP depth (AD1) and a fixed 2 / 2 arm at the 2060's line; "The 2 / 2 quality gate on the 2060 ... stays with you." |
| 15:54:48 | release | 6271392513 | AD1 / AD2: adaptive depth not adopted; fixed 2 / 2 best (code 128k +19.6 %; 64k code -5.0 %); "the default waits on your quality gate" (PR #209) |
| 19:55:07 | release | 6275985609 | AD3: 2 below / 4 past the line no better; 2 / 2 stays; "only the large 128k gains of 2 / 2 ... stand out of the noise" (PR #213) |
| 19:56:51 | 2060 | 6276018077 | P217 PASS: "the 2060 data supports the 8 GB preset defaults **replay on + draft 2 / tail 2** in the next bundle" |
| 22:14:43 | release | PR #214 (2c6b382) | bundle-20261019b: 8 GB defaults to replay rollback and draft 2 / 2; patch 0071 |
| 22:16:16 | release | 6278575184 | "**bundle-20261019b is out**" (zip d5a53c2b2ad238e2...); 4070 gates R1-R4, R6 (12 GB speed). "Over to your formal R6 on the zip." Request: a quick_tps sweep of the new default at 4k / 64k / 128k / 160k / 245k to update the 8 GB numbers |
| 22:46:32 | release (Cary) | 6279028757 | Wrap-up: "this issue closes after your two pending reports" (the formal R6 on 19b; P219). Decode at 128k "22.3-23.0 -> **31.8 tok/s** with replay + draft 2 / 2" |

- No #138 post asked the 2060 for the R6 groundwork; #202 named the need. The 2060 started it at 06:13 CDT (11:13Z), 2 h
  28 min after #202, on Cary's prompt.
- At the time of writing the formal R6 on the bundle-20261019b zip and the quick_tps sweep have not run (notebook 18:39
  CDT: "Then: wait for the bundle ..."; see E106).

## E103 Research pass 2 and the sub-3-bit KV probe

| | |
| --- | --- |
| Date | Notebook "2026-10-19 08:46 CDT Research pass 2 (Cary: "another research pass across arxiv / experimental githubs"); P216 (2-bit KV quality) queued". The findings are the agent's, logged in the notebook; the agent's own notes are not in this repo |
| Leads (as logged) | "(1) lossless self-speculation with a sparse draft KV kept in VRAM (TriForce / MagicDec / Vegas): exact; est. 1.45x decode at 245k if acceptance ~0.9; medium-large. (2) KV below 3 bits (TurboQuant 2.5-bit after rotation; KIVI): ~127k VRAM cells, est. +20-35 % decode at 200-245k; lossy. (3) int8 KQ in the Turing prefill FA (SageAttention idea): est. 1.15-1.25x cold read; large. (4) SuffixDecoding lookup; (5) tree verification at depth (EAGLE / STree); (6) draft length by depth via --spec-draft-p-min." All estimates are the agent's, not measured |
| Not worth it (as logged) | "ShadowKV / InfiniGen / Quest-class as the main path (P98: attention is spread), MagicPIG / CPU attention (P95 / P97), BitBLAS-class matmul (25 % of the read), GDN kernels (4 %), training-based methods" |
| Probe of lead 2 | P216: a full 2-bit KV fails G1 (best +1.83 % at 64k vs q3_0; rotation matters; Lloyd-Max worse). P218: V-only 2-bit passes G1 (+0.55 %). P219: V-only 2-bit fails G2 (2 confident wrong answers vs 0 for the rounding null). Notebook 17:46 CDT: "Sub-3-bit KV CLOSED (full 2-bit fails PPL; V-only passes PPL but fails retrieval)." |
| Engine | fork `kv-fake2` (pushed 2026-10-19): 75778b6ca (the P100 hook, cherry-picked from 4d1c8abe0), c05e7bb89 (mode 20, Lloyd-Max levels), 37a51194f (the V-only switch). The build output folders were `bin-fake2` and `bin-fake2v`; there is no branch `kv-fake2v` |
| Not tried in this range | Leads 1 and 3-6. The 4070 tried lead 6's neighbour (adaptive draft depth, AD1-AD3: not adopted) |
| Links | P100; P216; P218; P219; #138 17:27:46Z, 22:46:41Z |

## E104 Queue incidents: two first tries that failed at their start

| | P210 first try | P213 first try |
| --- | --- | --- |
| Queue log | 18:55:18 "filler filler_c_humaneval.sh preempted by 69jec3-p210-postzip-1018d.sh"; 18:55:19 "run" and "FAILED" | 06:13:20 "run 69jec6-p213-r6-replay.sh"; 06:13:28 "FAILED" (filler c had ended 06:13:19) |
| Cause (notebook) | "a cut-paste error in the script; the preempt watcher runs a pending file within 20 s" | "first queued too early: it failed at start (receipt deleted by me, cause not kept)"; bin-0070 was building 06:12:16-06:35:41 |
| Fix | "rebuilt in the scratchpad, bash -n, then queued" (file 18:55:57; run 18:56:01) | requeued as 69jec7 after the build (file 06:36:00); its script waits for "0070 exit" in build_ahead.log and stops if the build failed |
| Cost | ~1 s of a job slot; the fillers were stopped twice | 8 s; filler a ran 06:13:29-06:36:19 |

- The failed texts were not kept (both `.out` files are empty).
- Since the filler watcher (E84 in `events-p169-p182.md`) any file in `queue/pending` runs within ~20 s. A script must be
  complete and checked before it enters that folder.

## E105 GPU time in this range

Queue log 22:21:50 (10-17) to 18:35:35 (10-19), 44.2 h:

| from | to | what |
| --- | --- | --- |
| 10-17 22:21:50 | 10-18 05:13:55 | fillers (6.9 h): T5 work closed by the kernel session; nothing asked of the 2060 |
| 05:13:56 | 06:32:12 | P200 (1.30 h) |
| 06:32:12 | 07:37:36 | P201 (1.09 h) |
| 07:38:37 | 08:42:42 | P202 (1.07 h); filler b preempted 07:38:37 |
| 08:43:43 | 09:25:04 | P203 (0.69 h); filler c preempted 08:43:42 |
| 09:25:04 | 10:50:07 | P204 (1.42 h) |
| 10:51:08 | 12:02:25 | P205 (1.19 h) |
| 12:03:46 | 12:08:46 | P206 (0.08 h) |
| 12:10:07 | 12:59:44 | P207 (0.83 h) |
| 12:59:45 | 15:25:33 | fillers (2.4 h); the P207 result entry came at 15:25 |
| 15:25:33 | 16:18:08 | P208 (0.88 h) |
| 16:20:29 | 16:42:55 | P209 (0.37 h) |
| 16:42:55 | 18:55:18 | fillers (2.2 h); bundle-20261018d published 18:28 CDT |
| 18:55:19 | 18:55:19 | P210 first try (FAILED, E104) |
| 18:56:01 | 19:13:32 | P210 (0.29 h) |
| 19:13:32 | 10-19 01:08:37 | fillers (5.9 h): 18e needed no check; 18f published 23:44 CDT |
| 01:08:38 | 01:25:53 | P211 (0.29 h) |
| 01:26:55 | 01:42:08 | P212 (0.25 h) |
| 01:42:08 | 06:36:19 | fillers (4.9 h), with the P213 first try at 06:13:20-06:13:28 (E104); #201 merged 03:11 CDT, #202 03:45 CDT |
| 06:36:19 | 07:42:06 | P213 (1.10 h) |
| 07:43:07 | 08:20:26 | P214 (0.62 h) |
| 08:22:07 | 09:21:41 | P215 (0.99 h) |
| 09:21:41 | 11:33:56 | P216 (2.20 h) |
| 11:33:57 | 12:25:39 | P218 (0.86 h) |
| 12:25:39 | 13:46:53 | P217 (1.35 h) |
| 13:46:54 | 16:35:53 | P219 (2.82 h) |
| 16:35:53 | - | fillers (running at the time of writing) |

- Jobs 19.7 h, fillers about 24.5 h. No idle gap in the log.
- The watcher stopped a filler 0-20 s after each new queue file (15 preemptions).

## E106 Corrections in this range

- P200, #138 11:32:47Z: "A restart on the 2060 re-reads up to ~12k tokens at deep context at ~200-300 tok/s. That costs
  about as much as the 4070's whole restart turn." The layer logs give ~102-157 tok/s (76-117 s per ~12,000 tokens),
  2-3x the 4070's restart-turn mean (37.8 s). The verdict does not change. Found by this record writer.
- P201, notebook 07:38 CDT: "card back on slot 5 (175 W confirmed)": the receipt has no power.limit reading after the
  exit trap. Found by this record writer.
- P203: the line was 79,616-82,944 against P200's 86,016-86,528, so the -4.1 % session is not on the same line; the
  summary has no temperature line (a parser fault); the script header holds P200's G1 gate text. Found by this record
  writer.
- P204, #138 15:51:11Z: the run was at GROW 8192, not 4096 (my mistake, posted at the time).
- P206, notebook 12:09 CDT: "the 64k summary decode 36.1 vs ~39.5 is a 64-token answer (0067 stops drafts at the end)":
  P202 (before 0067) and P209 (with 0067) decoded the same 64-token answer at 39.5 / 39.3 tok/s (server logs). The cause
  of the 36.1 is not known. Found by this record writer.
- P207 / P208, #138 21:18:46Z: "CPU load was low" holds for P208 (mean 9.1 %) only; P207 had no CPU log. The "GPU idle"
  throttle reason also shows in stock long reads. The P208 script header lists P202's arms. Found by this record writer.
- P211: the script header says "the 18d zip's own launcher"; it ran 18f. Found by this record writer.
- P213, #138 12:42:50Z: A's 128k identity read a warm 32k prefix (95,812 tokens evaluated), so it is not a cold read; the
  soak's restart turns are 3.1-3.8 s slower than P212, not "equal ... within noise"; the plan calls P212 "line
  80,640-class", but P212 ran at 80,128. Found by this record writer.
- P215, #138 14:23:11Z: "the greedy text differs between draft sizes at every depth": every larger draft differs from
  1 / 1, but 2 / 1 = 2 / 2 at 4k and 2 / 1 = 2 / 2 = 3 / 3 at 64k. Found by this record writer.
- P216 / P218 / P219, #138 17:27:46Z and 22:46:41Z, notebook 10:39 and 18:39 CDT: "kv-fake2v" is not a branch. The
  V-only commit 37a51194f is on `kv-fake2`; `bin-fake2v` is only the build folder. The 18:39 CDT entry "Pushed ...
  r6-0070, kv-fake2, kv-fake2v" pushed two branches (`r6-0070`, `kv-fake2`); `turing-mmq` was already on the fork.
- P100 (2026-10-10) and P216: P100's record says "no rotation"; P216 shows that P100's numbers equal the rotation-on arm.
  P216's own header calls the rotation-off arm "P100's setting". A line is added under P100's "Corrections later".
- P219: the line was not pinned (61,184-63,232 by server), so the null arm is not rounding-only on n24. The verdict holds
  on the code set, where v2 and null share 62,976. Found by this record writer.
- Notebook 18:39 CDT: "Then: wait for the bundle with replay + draft 2 / 2": bundle-20261019b was published at 22:15:39Z
  (17:15 CDT), 1 h 24 min before that entry. Found by this record writer.

## E107 Lessons recorded in this range

- P204: a helper that runs part of the product outside the launcher does not get the launcher's per-card defaults;
  export them by hand (notebook 10:51 CDT: "an external layer runner must get the launcher's layer env (GROW, AFTER,
  SAVE_PATH) explicitly") and read the helper's log before the run counts.
- P210 / P213 (E104): with the preempt watcher, write and check (`bash -n`) a queue script outside `queue/pending`, and
  let a job that needs a build wait for the build's exit line.
- P212: test a restore's exactness against a cache-off run on one server with no restarts, at the same line.
- P217 / P219: judge an answer change against an in-block rounding-null arm (`GGML_CUDA_FA_CHUNK=16384`); count
  confident wrong answers and changed items.
- P203 / P219: pin the VRAM line in every arm of an answer or speed A/B, or log it per server.
- P207 / P208: put the stock long read in the same block, and read the server's prompt-progress lines to see where a
  long read loses.
- P213: check the "evaluated" count before you call a det read cold (requests in one server share a prefix).
- P215: when an engine change makes a lever cheap (a draft token: 144 -> 7 MiB), re-test what it made costly.
- P218 / P219: a perplexity pass is not a retrieval pass; gate lossy KV on long lookups too.
- P201-P208: switch clock profiles only with no server up, force stock before every server, end on stock with an EXIT
  trap, and gate "applied" on the measured power limit and SM clock.
