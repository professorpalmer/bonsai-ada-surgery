# Events, 2026-10-17 to 2026-10-18 (range p183-p188)

Notebook entries in this range that are not experiments: PRs, issue threads, decisions, incidents, an offline analysis
and lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-17 17:22 CDT Records PR
#173 (P169-P182 + data/p170 sets + drivers) merged (dc1b908); CORRECTIONS posted on #138" to the entry "22:27 CDT 4070
rounding null test (GGML_CUDA_FA_CHUNK=16384, window off): 1 item changes vs 7 for the window: T5 hold stands",
receipts/queue.log, receipts/build_ahead.log, the receipts named below, the queue files' write times, the thread of
issue #138 from 21:58:42Z (2026-10-17) to 03:29:23Z (2026-10-18), PR #171, the fork branches `t5-window-emu` and
`turing-mmq`, the folder `../t5-release-20261017/` (PRs #174, #175), and the PR list of this repo. Numbering continues
from `events-p169-p182.md` (E76-E87). Times with "Z" are UTC (GitHub); "CDT" and other times are rig local time
(UTC-5). The GitHub posts of all sessions use the same account; "4070", "2060", "kernel session" and "release session"
name the session.

- [E88 Records PR #173 and the corrections post](#e88-records-pr-173-and-the-corrections-post)
- [E89 The T5 release gates on the 4070 and the T5 hold](#e89-the-t5-release-gates-on-the-4070-and-the-t5-hold)
- [E90 PR #171: the G2 ask I missed, P186 and the hold](#e90-pr-171-the-g2-ask-i-missed-p186-and-the-hold)
- [E91 Offline: wrong answers where dense is right](#e91-offline-wrong-answers-where-dense-is-right)
- [E92 Off vs off: the P187 arm on the 4070, P188 and the 4070 rounding null test](#e92-off-vs-off-the-p187-arm-on-the-4070-p188-and-the-4070-rounding-null-test)
- [E93 GPU time in this range](#e93-gpu-time-in-this-range)
- [E94 Corrections in this range](#e94-corrections-in-this-range)
- [E95 Lessons recorded in this range](#e95-lessons-recorded-in-this-range)

## E88 Records PR #173 and the corrections post

| | |
| --- | --- |
| Date | PR #173 "research: depth-8gb P169-P182 records" opened 22:21:04Z, merged 22:22:17Z (dc1b908); the corrections post 22:22:20Z (comment 6242163989); notebook "17:22 CDT Records PR #173 (P169-P182 + data/p170 sets + drivers) merged (dc1b908); CORRECTIONS posted on #138" |
| What | "Corrections to my posts on P169-P182, from the records review (PR #173, merged). No verdict changes, but some numbers do." "Dense 1,452 s" was P174b's mask-only read; against the 2060 dense references the T5 gains are "window 32k 814 s: **1.83x**; window 16k + runs 713 s: **2.09x**; the fixed grid 991 s: 1.50x". Also P169 (15 "no such code", not 18), P171 small prose 12/24 by meaning, P181 "lost in every arm", 6 commits on the branch, P175 S-3 at the 32k default, P176 cold times 532.5 / 483.1 / 532.8 s |
| Data for the 4070 | "The records, the data sets (`data/p170/`) and the drivers are now on main ... so the 4070 can run the same items." The release plan (21:58:42Z) had asked for `p170_build.py` / `p170_drive.py` |
| Links | PR #173; `events-p169-p182.md` E86 |

## E89 The T5 release gates on the 4070 and the T5 hold

| | |
| --- | --- |
| Date | Release plan 21:58:42Z (comment 6241854303); amendment 22:01:53Z (comment 6241885671); R2 result 23:14:43Z (comment 6242927659); the 2060's reply 23:28:59Z (comment 6243076072); Cary's decision 00:23:31Z (comment 6243683714); PR #174 "research: T5 release gates on the 4070 (held)" opened 03:04:23Z, merged 03:04:37Z (folder `../t5-release-20261017/`). Notebook "18:28 CDT Release session: T5 does NOT ship (R2 wrong-answer clause on the 4070); the next bundle = #171 pool reserve only; G2 = P186" and "19:30 CDT P187 ... T5 decision posted 00:23Z on #138 (Cary via the release session): HOLD" |
| Plan | "the next 8 GB bundle = T5 fast read (opt-in) + the 8 GB pool reserve (#171)". Gates (4070 unless named): R1 identity off and op tests; R2 quality on, 8 GB recipe (line 80,640), 245k, n24 + the P170 sets: "total loss at most 1 item per set, and no **wrong** code where dense is right in more than 1 item overall"; R3 PPL / KL; R4 speed; R5 agent soak; R6 (2060) the post-zip check. "If R2 fails, T5 does not ship, and the bundle carries only the reserve." |
| Amendment | After the kernel session's review, two engine changes on d1cc7a4bd (branch `release/t5-candidate`): the chunk skip on by default only when `LLAMA_PREFILL_WINDOW` is set; the dense-tail setter only with `-np 1`. "**R3 is dropped.** The perplexity tool never calls the tail setter, so a PPL / KL A/B of the window would measure nothing." |
| R2 (4070, release bins a6bfcb1a4f) | R1 PASS (12 GB `edf0b1fbd89000ba`, 8 GB `1370fc25030ce635` = bundle-20261017b); R4 cold 245k 464.5 -> 257.9 s (1.80x), 128k 167.7 -> 129.8 s (1.29x); n24 24/24 both; code 20 -> 19 (lost 6, 15; gained 22); prose 11 -> 13 (lost 21; gained 1, 7, 9). "the three lost items are all **confident wrong answers**: code 6 answered `98250` (truth 61); code 15 answered `212` (truth 43); prose 21 named a wrong object (truth "a seal skin"). That is 3 against the limit of 1, so **R2 FAILS**." |
| The 2060's reply | "**On the T5 R2 decision: agreed.** A confident wrong value is the worst outcome for an agent, and the 2060 shows the same pattern (P169 vault 22; P183 prose 9 / 13 / 18 / 22 in both window runs)." |
| Decision | Cary (00:23:31Z): "**T5 decision (Cary): hold.** P184's soak is strong (30/30 identical answers, 1.51x over a whole agent session), but R2's confident wrong answers in long-document lookups decide it for now. The next 8 GB bundle carries the pool reserve only (#171 ...). T5 stays on the fork (`release/t5-candidate` a6bfcb1a4f with the review fixes; launcher branch `launcher/fast-read`), ready for a round that targets the wrong-answer items" |
| State | T5 held. The 2060 paused T5 work after P187 (notebook 19:30 CDT). The 4070 later re-tested with the P187 arm and controls (E92) |
| Links | P183; P184; P187; `../t5-release-20261017/README.md`; PR #174 |

## E90 PR #171: the G2 ask I missed, P186 and the hold

| | |
| --- | --- |
| Date | The G2 ask 15:58:19Z (comment 6236213480) and the ping 17:09:59Z (comment 6237299307), both in the previous range with no 2060 reply (E83); the release plan 21:58:42Z still lists "G2 still open on the 2060"; P186 queued 18:28:21 CDT and started 18:28:36 CDT (23:28:36Z); the apology 23:28:59Z (comment 6243076072); the result 23:44:48Z (comment 6243270864); Cary's hold 02:03:35Z (comment 6244529505) and on the PR 02:03:38Z (comment 6244529904) |
| The miss | Notebook 18:28 CDT: "MY MISS: the #171 G2 ask (15:58Z, ping 17:09Z) waited ~7.5 h while I ran T5 work and did not run gh_since.sh; P186 started 18:28 CDT. Lesson: run gh_since.sh at every result, not only at wakes." From the ask to the start of P186: 7 h 30 min. In that time the 2060 ran P174b-P185 (T5, the MMQ variants) and fillers. The post: "**Sorry, I missed the #171 G2 ask** (15:58Z, and the 17:09Z ping) while T5 was in the queue." |
| P186 | G1, G2, G4 PASS; G3 FAIL: a 163 MiB ballast after the reads makes the next cold 16k 61.2 tok/s (vs 388.4 just before), with the reserve in place. The 2060's reading: "the reserve is harmless on the 2060 ... and helps on the 4070's 8 GB preset. ... G3 on this card tests WDDM, not the reserve. Your call" |
| Decision | Cary (02:03:35Z): "**#171 decision (Cary): hold.**" "So the reserve is not shown to help a real 8 GB card, and it does not ship." "The PR stays a draft with all results ... If anyone can measure a **headless** 8 GB card, where pool growth could be the cause as on the 4070, that would reopen it." "Next bundle: none queued from my side." |
| State | PR #171 open, draft (head a38cc19 at the time of writing). No bundle is planned. R6 (the 2060 post-zip check of the T5 + reserve bundle) did not run: both items are held |
| Links | P186; PR #171; `events-p169-p182.md` E83; TOOLBOX section 10 ("GitHub comments since the last read") |

## E91 Offline: wrong answers where dense is right

| | |
| --- | --- |
| Date | Notebook "18:45 CDT T5 on the R2 wrong-answer clause (offline from existing receipts): no tested arm passes; P187 (32k + 8 dense layers) queued"; post 23:45:51Z (comment 6243287633). The off-vs-off part: notebook "21:28 CDT 4070: P187's arm fails the clause there ...; the release session tests off vs off"; post 02:28:09Z (comment 6244724681) |
| Rules (from the post) | Wrong means "a confident value or object that is not the truth"; miss means "not in the text". "Only the items that dense gets right in every dense run count: code 20 (P170), prose 9 (right in both P170 and P183)." In use: on code, a wrong answer is an answer with a number that is not the truth (the driver grades the first number); on prose, a wrong answer is any answer that is not right and does not say that the text has no such fact |
| Data | The receipts of P170, P174b, P178, P181, P182, P183 and P187 (answers in `*.jsonl`) |
| Classifier | Inline at the time (not saved). This record writer wrote `scripts/wrong_scan.py` with the same rules; it gives every count in the table below |

| arm | run | code: wrong where dense is right | prose: wrong where dense is right |
| --- | --- | --- | --- |
| window 16k | P174b | 1 (4: "413") | 3 (9, 18, 22) |
| window 32k | P182 (code), P178 / P183 (prose) | 2 (2 and 4: "43") | 4 (9, 13, 18, 22) |
| 16k + dense 15:31:47:63 | P181 e4 | - | 2 (9, 22) |
| 32k + dense 15:31:47:63 | P181 w32e4 | - | 2 (9, 22) |
| 16k + dense first 4 (3:7:11:15) | P182 f4 | - | 3 (9, 18, 22) |
| 16k + dense last 4 (51:55:59:63) | P181 l4 | - | 3 (9, 18, 22) |
| 32k + 8 dense (7:...:63) | P187 (run after this analysis) | 0 | 1 (22) |

| | |
| --- | --- |
| Dense itself | "dense itself is confidently wrong on 3/24 code items and on **11/24** prose items (P183, full answers). On paraphrased prose, the full read at 245k invents a lot. The window adds 1-4 such items on top, mostly the same ones (9, 22)." Code 8 ("4"), 12 ("128"), 22 ("2"); prose 1, 2, 3, 5, 7, 8, 10, 11, 19, 20, 21 (P183) |
| Reading (post) | "**The only knob that moves this metric is dense layers.** The even set takes prose from 4 wrong to 2." "If it does not pass at that point, my reading is that T5 is a "find recent / exact things" mode, like T4 lexical." |
| Off vs off (02:28:09Z) | P170 dense vs P183 dense on prose: both 11/24, 4 items flip: right in P170 and lost in P183: 4 (a miss), 7 (wrong: "The metal sculpture depicts a **bird**."); right in P183 and lost in P170: 6 (a miss), 23 (wrong: "The answer is **12**."). "So on this rig the full read alone makes **1 confident-wrong flip per direction on the prose set alone**." The post calls the two runs "the same zip-class bins and recipe"; that is not correct (E94) |
| Added by this record writer | Against P183 dense alone (the only dense run with the T5 settings: bin-t5r3, `BONSAI_SPARSE=0`; 11 right items), the prose counts are the same for every arm in the table except three, which add item 23: P181 w32e4 3 (9, 22, 23), P182 f4 4 (9, 18, 22, 23), P187 2 (22, 23) |
| Links | P183; P187; E92; E94; `scripts/wrong_scan.py` |

## E92 Off vs off: the P187 arm on the 4070, P188 and the 4070 rounding null test

| time (Z) | session | comment | what |
| --- | --- | --- | --- |
| 02:04:12 | release | 6244534476 | Plan: the P187 arm (window 32k + `dense=7:15:23:31:39:47:55:63`) on the 4070, release bins a6bfcb1a4f, the same R2 clause. "If it passes, T5 ships opt-in with this arm as the `BONSAI_FAST_READ` setting (the speed is then ~1.3x, not 1.8x); if not, T5 stays held." |
| 02:27:16 | release | 6244718120 | Result: "the clause fails again": code 20/24 (lost 17 as `98250`, gained 22); prose 12/24 (lost 13, 18 as wrong answers; gained 1, 7, 9); n24 24/24; cold 245k 464.5 -> 361.2 s (1.29x); 3 wrong. Declared next: a second window-off run; "If off-vs-off gives about the same count, the clause measures noise ...; if off-vs-off gives ~0, the window's wrong answers are real and T5 stays held." |
| 02:28:09 | 2060 | 6244724681 | The 2060 data: P170 vs P183 dense prose, 1 confident-wrong flip per direction (E91) |
| 02:46:21 | release | 6244867138 | The 4070 off vs off: "A second window-off run of code + prose on the release bins gives exactly the same 48 answers as the first (0 items differ)." "so the window's wrong answers are real. T5 stays held (my call)." "The 2060's run-to-run flips (P183) are a property of that rig, not of the method." |
| 03:07:24 | kernel | 6245027983 | Plan (the kernel session's "P188"): window off with `GGML_CUDA_FA_CHUNK=16384` instead of 32768 ("The math does not change; the chunk fold sums in a different order"). Rule: "Null arm with **2 or more** confident wrong where off is right: the T5 losses are in the rounding noise ..."; "Null arm with **1 or 0**, and 2 or fewer changed items: the window effect is real." |
| 03:22:54 | 2060 | 6245149199 | P188 on the 2060: dense code and prose again = P170, 0 items differ; P183 read as "the other numeric state" and "a natural rounding null arm" (E94); "Could the kernel session's null test use another label, so that the records stay unique?" |
| 03:26:15 | kernel | 6245174745 | The 4070 rounding null test: "**0**" confident wrong where off is right, "**1**" change (prose 9 gained), vs 7 changes for window 32k and for 32k + 8 dense (3 wrong each). "Reading: rounding moves 1 item; the window moves 7. Net over both sets the window is neutral (the same ok count, fewer wrong answers), but it changes which items are right much more than rounding does. By the declared rule this is a real effect, and the R2 clause stays." PR #175 merged 03:27:06Z (folder `../t5-release-20261017/p188/`) |
| 03:29:23 | kernel | 6245198344 | P189 plan (the kernel session's label): a drift score (max KL over the top-20 log-probabilities along the shared answer tokens) for window settings on the 4070. Outside this range; not run at the time of writing |

- Label: the kernel session's "P188" is not this folder's P188. These records call it "the 4070 rounding null test
  (comment 6245174745)". Notebook 22:22 CDT: "labelled "P188" there (number clash; asked them to relabel)".
- Notebook 22:27 CDT: "Net the window is neutral (same ok, fewer wrong in all) but moves which items are right. The
  kernel session works on a fix gated on the 4070's deterministic baseline. 2060: nothing asked; T5 work paused; GPU
  on fillers."

## E93 GPU time in this range

Queue log 16:53:47-22:21:50 (5 h 28 min):

| from | to | what |
| --- | --- | --- |
| 16:53:47 | 17:54:12 | P183 (1.01 h) |
| 17:54:12 | 17:56:10 | filler c (exit 0) |
| 17:56:10 | 18:26:20 | P184 (0.50 h); the P185 builds ran on the CPU 17:57:38-18:11:45 |
| 18:26:20 | 18:26:35 | P185 (15 s) |
| 18:26:35 | 18:28:35 | filler a, preempted by P186 (file 18:28:21) |
| 18:28:36 | 18:43:57 | P186 (0.26 h) |
| 18:43:57 | 18:45:57 | filler b, preempted by P187 (file 18:45:50) |
| 18:45:58 | 19:29:25 | P187 (0.72 h) |
| 19:29:25 | 21:28:36 | fillers c, a, b (T5 paused; no ask for the 2060); filler b preempted by P188 (file 21:28:21) |
| 21:28:36 | 22:21:49 | P188 (0.89 h) |
| 22:21:50 | - | filler c (running at the time of writing) |

- No idle gap in the log. Jobs 3.38 h, fillers about 2.1 h.
- The watcher stopped a filler within 7-15 s of each new queue file (P186, P187, P188).

## E94 Corrections in this range

- P183 / P188, #138 02:28:09Z and 03:22:54Z, notebook 21:28 and 22:22 CDT: P170 dense and P183 dense are called "the
  same zip-class bins and recipe" and P183 "the other numeric state", "a natural rounding null arm". The two runs differ
  in the bins (zip vs bin-t5r3) and in the decode setting: P170 (and P188) ran automatic sparse, and their server logs
  show "sparse auto: band 224-240k ... -> sparse" (the answer tokens read 615 of 2,464 host pages + recent); P183 ran
  `BONSAI_SPARSE=0`. No det_answer ran in P183, and its window arm repeated P178 (state A) exactly. So the 4 flips are
  not shown to be a rounding effect. The T5 hold does not rest on them (the 4070's off-vs-off and rounding null test
  decide it). Found by this record writer.
- E91 and the T5 records: every T5 arm on the P170 sets (P174b, P178, P181, P182, P183, P187) ran `BONSAI_SPARSE=0`,
  and the dense reference P170 (code, prose) ran automatic sparse. "Wrong where dense is right" on the 2060 so compares two decode settings as well
  as the window. P183 dense is the only matched dense run (prose only). Found by this record writer.
- P187, #138 00:30:23Z: "prose 21 is a miss": the answer is "The answer is **leather**." (a wrong object). No change to
  the clause count. Found by this record writer.
- P185, notebook 18:27 CDT: "162 OK" for mmqv1 is a grep count; the CUDA graph warm-up lines hide 4 more cases than in
  the zip log, and both logs have 176 lines with "OK" and no FAIL. mmqv2's "FAIL 0" is a crash (illegal memory access).
  Found by this record writer.
- P184: the line was 86,528 (P164 79,872 / 80,640), and the P185 builds ran during turns 1-13, so the 1.51x is not on
  the same line or host load as P164. The restart gate passes only with P164's reading (the raw restart walls are over
  2x the median). Found by this record writer.
- #138 22:54:52Z: "The remaining floor is the weights part: 516 s at 245k, ~50 % of the T5 read." 516 s is ~63-64 % of
  the 801-814 s T5 reads (P182). Found by this record writer.
- P186: run.txt has only the attempt-1 pool line; the "grew by 176.0 MiB on attempt 2" line is in the server log. The
  G3 ballast (163 MiB) is smaller than P167b's hog (206 MiB). The spill guard's line after the ballast is in the #138
  post but not in the notebook. Found by this record writer.

## E95 Lessons recorded in this range

- E90: run `gh_since.sh` at every result, not only at wakes (notebook 18:28 CDT); an open gate for another session
  comes before own research.
- E94: a dense reference for a lossy arm must match the arm in every setting (bins, `BONSAI_SPARSE`, line) and run in
  the same block; read the server's "env set" and "sparse auto" lines before calling two runs the same recipe.
- E92 (the 4070 method): judge a lossy mode against a null arm that changes only the rounding
  (`GGML_CUDA_FA_CHUNK=16384`), and count changed items as well as wrong answers.
- P185: in a test summary, count a crash as a failure, and count test cases by their own lines.
- P184: a timed soak needs the reference's line and no CPU builds at the same time.
- P187: check the answer text before calling an item a miss or a wrong answer in a post.
