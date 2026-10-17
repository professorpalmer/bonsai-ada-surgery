# Events, 2026-10-17 (range p169-p182)

Notebook entries in this range that are not experiments: releases, PRs, issue threads, decisions, incidents and
lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-17 05:09 CDT P169 queued:
T4-A fast read on the 2060 (before round 2 posts)" to the entry "16:53 CDT P182: window 32k / sink 1k / tail 1k = n24
24/24 (814.3 s), code 19/24 (801.1 s), prose (P178) 9/24 (807.8 s)", receipts/queue.log, receipts/build_ahead.log, the
receipts named below, the queue files' write times, the thread of issue #138 from 10:01:29Z to 21:54:09Z, the commits of
the fork branch `t5-window-emu`, and the PR list of this repo (titles and times). Numbering continues from
`events-p162-p168.md` (E67-E75). Times with "Z" are UTC (GitHub); "CDT" and other times are rig local time (UTC-5). The
GitHub posts of all sessions use the same account; "4070", "2060", "kernel session" and "release session" name the
session.

- [E76 Records PR #165 and the corrections post](#e76-records-pr-165-and-the-corrections-post)
- [E77 Spill guard merged, bundle-20261017b, R4 and serve-1017b](#e77-spill-guard-merged-bundle-20261017b-r4-and-serve-1017b)
- [E78 The cold-read cost model](#e78-the-cold-read-cost-model)
- [E79 T4 fast read: the 4070 rounds 2-8, the paraphrase gate, the 2060 cross-check](#e79-t4-fast-read-the-4070-rounds-2-8-the-paraphrase-gate-the-2060-cross-check)
- [E80 Cary's ask and the cold-read research](#e80-carys-ask-and-the-cold-read-research)
- [E81 The T5 fork branch: commits and bins](#e81-the-t5-fork-branch-commits-and-bins)
- [E82 The rig drift between two numeric states](#e82-the-rig-drift-between-two-numeric-states)
- [E83 The pool reserve (PR1, PR2, PR #171) and the open G2 ask](#e83-the-pool-reserve-pr1-pr2-pr-171-and-the-open-g2-ask)
- [E84 The filler time 13:10-13:47 and the filler preemption](#e84-the-filler-time-1310-1347-and-the-filler-preemption)
- [E85 The T5 proposal and P183](#e85-the-t5-proposal-and-p183)
- [E86 Corrections in this range](#e86-corrections-in-this-range)
- [E87 Lessons recorded in this range](#e87-lessons-recorded-in-this-range)

## E76 Records PR #165 and the corrections post

| | |
| --- | --- |
| Date | PR #165 "research: depth-8gb P162-P168 records" opened 10:23:33Z, merged 10:24:19Z (rebase, f742ffa); notebook "05:24 CDT Records PR #165 (P162-P168) merged (rebase, noreply author, f742ffa); corrections posted on #138"; the post 10:24:37Z (comment 6232785183) |
| What | The records review corrections, posted to #138: "P163: ... both were at 64k"; "P164: the restores took 2.05-3.36 s"; the turn-5 answer; "The restart gate "(+ any save)" passes only if the layer's re-read and save time is left out"; "the forward-slash fault also voids the G4a "0 lines" results of P166 and P167"; the OOM text only in P166b's log; "P168: the 64k reads were 2.2-2.3 % faster than the reference ... The "~148 MiB free at the first /health" and "~170 MiB growth" figures were not logged. They were my estimates." |
| Merge note | Notebook: "Squash merge with the noreply author fails (GraphQL "Invalid email"); rebase merge keeps it." |
| Links | PR #165; `events-p162-p168.md` E74 |

## E77 Spill guard merged, bundle-20261017b, R4 and serve-1017b

| | |
| --- | --- |
| Date | PR #164 (spill guard) merged 10:40:00Z (notebook 05:53 CDT "Spill guard #164 merged"); release PR #167 opened 10:49:59Z, merged 10:50:12Z; the release post 10:51:42Z on #138 (comment 6233032374) and 10:51:43Z on #105; P172 queued 12:25:55Z (notebook 07:25 CDT); R4 PASS 13:07:34Z (comment 6234245664); PR #168 "docs: release-20261017b R4 PASS (2060 post-zip)" 13:08:24Z / merged 13:08:37Z |
| What | bundle-20261017b = the spill guard v6 + the layer read ahead, no engine change: "Every `bin/` file is byte-identical to bundle-20261017. Changed files: README.md, start-server.ps1, layer/bonsai_layer.py, layer/slot_cache.py." Zip 616,671,821 B, SHA-256 6285cd5d...e79ce. "The launcher is the v6 spill guard (the server is found as the launcher's own child process). Any `BONSAI_BIN` form works." |
| R4 (P172) | PASS: sha match, 0 control bytes, 16/16 bin files = bundle-20261017, cold 64k 308.6 tok/s (-0.2 % vs P168), 0 spill lines, the line 28 s after a 58 MiB ballast, 0 CUDA errors; line 87,808 |
| serve-1017b | Notebook 08:07 CDT "Next: serve-1017b folder for Cary"; 08:37 CDT "serve-1017b ready". The folder content is not described in this range |
| Links | P172; PR #164, #167, #168; `../release-20261017b/` |

## E78 The cold-read cost model

| | |
| --- | --- |
| Date | Post 10:45:05Z (comment 6232969793); notebook "05:53 CDT Cold read cost model posted; P170 (text match) and P171 (small scorer) queued after P169" |
| Fit | "time per prompt token = a + b x depth. a = 2.11 ms (the 2k-token rate, 473 tok/s); b = 3.25e-8 s per token pair of attention." So a cold read of N tokens takes a x N + b x N^2 / 2 |
| Data | 64k (P168): measured 207.0 s, a x N 135.3 s, rest 71.6 s (b 3.50e-8); 128k (P168): 532.4 s, 269.2 s, 263.2 s (b 3.25e-8); 245k (16b): 1,489 s, 516 s (35 %), 973 s (65 %) (b 3.26e-8) |
| Reading | "The fit holds past the VRAM line (b is the same at 128k and 245k). So the system-RAM KV tail is not a large cost of the read." Attention runs at about 12 TFLOP/s, the rest at about 25 TFLOP/s. "The floor for a method that reads every token with the full model: 516 s at 245k ... With attention 2x faster, 1,003 s (1.48x vs today)." A kept read of 16,384 tokens costs ~39 s (32,768: ~87 s). T4-A's floor is its scoring pass (180.8 s, P169) |
| Geometry | Notebook: "from the GGUF: 64 blocks, full attention every 4th, 24 heads, 4 KV heads, 256" |
| Later use | T5 cost (14:08:33Z): window 16k + sink 1k ~650 s, window 32k + sink 1k ~760 s at 245k; P182: "516 s weights + 245k x 33k pairs x 3.25e-8 = ~779 s" vs 801-814 s measured |
| Links | P168; P169; P170; P173; P182; issue #138 |

## E79 T4 fast read: the 4070 rounds 2-8, the paraphrase gate, the 2060 cross-check

| | |
| --- | --- |
| Date | Round 2 10:41:34Z (records PR #166 merged 10:41:30Z); P169 on the 2060 11:51:29Z; round 3 plan 13:58:23Z, result 14:38:56Z; round 4 plan 14:45:10Z, result 15:41:23Z; round 5 16:12:42Z; round 6 16:28:36Z; round 7 16:42:42Z; round 8 + the paraphrase plan 17:08:49Z; the paraphrase gate 17:26:47Z; PR #172 (rounds 3-8 + the paraphrase gate) merged 17:27:44Z |
| Round 2 (4070, 245k) | `bmax=1`, keep 16,384: 9/24 (76.1 s); keep 32,768: 14/24 (93 s); dense 24/24 (467.8 s). "Decision: T4-A stays an off-by-default experiment (fork branch `t4-fastread-b`), not for a release." |
| 2060 (P169) | T4-0 PASS; `keep=16384,bmax=1`: 5/24, 237.6-239.6 s per question (6.2x), one wrong code. "I agree with the decision: T4-A stays off by default. I will not run the keep 32k arm now." |
| Rounds 3-8 (kernel session, 4070) | Round 3 (question rows + head max, keep 32k): 12/24, 5 wrong codes, "Attention-only selection is closed for this model." Rounds 4-6 (lexical n-grams in the server): 2/24, 6/24, 14/24 (tokenization and neighbor-order causes). Round 7 (n-grams 1-4, `lexdf=8`, keep 16k): n24 24/24 in 16.4 s (28x), copies 11/20 (dense 19/20). Round 8 (`lexdf=32`, keep 32k): 24/24, copies 12/20, 32.6 s |
| Paraphrase gate (4070) | `bench/needle_paraphrase.py`, 245k: dense 10/24, lexical 3/24 with 2 wrong codes. "lexical fast read is a "find this exact fact / name" mode, not a general read. T4 stays an experiment, off by default." |
| Open (4070) | "the small-model scorer (P171) on the same three sets, needles, copies and paraphrase, which is the fair test for a semantic selector; the paraphrase set at 64k for a sharper dense-vs-selector gap." |
| Links | P169; P170; P171; `../t4-20261017/`; PR #166, #172 |

## E80 Cary's ask and the cold-read research

| | |
| --- | --- |
| Date | Notebook "08:37 CDT P171 code-set scoring ...": "Cary checked in 08:36 ("mic drop yet?"): status given, no mic drop on cold reads; serve-1017b ready." Notebook "09:08 CDT Cold-read research (agent, web + GitHub) and T5 prefill window (mask emulation) built; P173 + P174 queued" |
| Ask | Cary: "keep grinding, think of anything else for cold read; research GitHub for recipe fixes" |
| Shortlist (research agent) | "(1) Star Attention / SWAA: sink + local window for context tokens, FULL attention for the query and decode (NIAH near dense on Llama; a naive window without dense query collapses); cost model: W 16k + S 1k cuts 245k 1,489 -> ~650 s, W 32k -> ~760 s; (2) keep 2-4 of the 16 full-attention layers dense if needles drop; (3) XAttention antidiagonal block selection (Qwen3.5-27B full-attn layers need only 256-2048 tokens per query at 128k with an oracle selector, arXiv 2606.07703); (4) profile the weights part (MMQ int8 at ~22 % of the Turing int8 peak); (5) SpecPrefill (high risk, same class as T4)." |
| Not worth it | "SwiftKV, KV prediction, LayerSkip, SeerAttention, MInference, FastKV / LazyLLM / PyramidInfer, CacheBlend / APE, DuoAttention, bitnet.cpp." |
| Why T3 lost needles | "it made the question's own prompt rows sparse too; Star / SWAA keep them dense." |
| Post | #138 14:08:33Z (comment 6234880727) with the paper links (Star Attention arXiv 2411.17116, SWAA arXiv 2512.10411) and the P174 gates. Star: "-0.77 % on RULER at 256k" (from the post) |
| What followed | Item 1 = T5 (P174-P182); item 2 = the `dense=` option (P178 R-3, P181, P182 f4); item 4 = P173. Items 3 and 5 were not started in this range |
| Links | P173; P174; P181; issue #138 |

## E81 The T5 fork branch: commits and bins

Fork `professorpalmer/llama.cpp-ada-ternary`, branch `t5-window-emu`, on 96f6e49cd (the bundle-20261017 engine). Commit
times from GitHub (CDT = Z - 5 h); build times from receipts/build_ahead.log (each build is `HEAD` at its start time;
`scripts/build_t5*.sh`).

| commit | time (CDT) | what (commit message, short) | bin (build) | runs |
| --- | --- | --- | --- | --- |
| c675d5c78 | 09:06:52 | "T5 prefill window (experimental, mask-only quality emulation, off by default): LLAMA_PREFILL_WINDOW=window=W,sink=S,tail=T masks cells S <= pos < p - W for prompt ubatches before the dense tail; the server sets the tail from the prompt length" | bin-t5 (09:07:00-09:08:51) | P174, P174a, P174b |
| d048068ca | 11:17:22 | "cuda: chunked prefill attention skips a K/V chunk that no row of the packed mask keeps (exact ...); GGML_CUDA_FA_CHUNK_SKIP=0 turns it off" | bin-t5s (11:17:28-11:19:17) | P175, P176, P177 |
| fd17c67db | 13:45:50 | "T5 prefill window: dense=il:il:... keeps the listed attention layers on a second, unwindowed mask" | bin-t5d (13:45:55-13:47:38) | none (superseded by bin-t5r) |
| 80998aa79 | 13:48:07 | "cuda: the chunked prefill attention runs only the kept 256-cell blocks of the packed mask, merged into runs of at most GGML_CUDA_FA_CHUNK cells (exact ...)" | bin-t5r (13:48:07-13:50:03) | P178 |
| 0ad1aa527 | 13:54:02 | "cuda: the chunk scan skips itself while the stream is captured into a CUDA graph (it needs a host sync)" (the capture guard) | bin-t5r2 (13:54:02-13:55:53) | P179 |
| d1cc7a4bd | 14:57:19 | "T5: the hybrid memory input fills and reuse-checks the dense-layer mask too (it stayed unset: garbage in the dense layers)" | bin-t5r3 (14:57:23-14:59:03) | P180, P181, P182 |

The engine code is not copied into this folder. The #138 posts: "94 lines" (c675d5c78) and "bundle-20261017 engine +
about 200 lines" (HEAD d1cc7a4bd).

## E82 The rig drift between two numeric states

| time (CDT) | run | bins | det_answer 4k | det_answer 32k | state |
| --- | --- | --- | --- | --- | --- |
| 05:09-05:15 | P169 | zip; bin-t4b (env unset) | d72631aab936fc4e | d77df25fc3f18819 | A |
| 10:28-10:30 | P174 | bin-t5 (env unset, SPARSE=0) | 55d8056e05da9685 | 4d487e489a89d005 | B |
| 10:31-10:32 | P174a | zip + SPARSE=0; bin-t5 | 55d8056e05da9685 (both) | - | B |
| 10:35-10:40 | P174b | zip; bin-t5 | 55d8056e05da9685 (both) | 4d487e489a89d005 (both) | B |
| 12:07-12:13 | P175 | zip; bin-t5s | d72631aab936fc4e (both) | d77df25fc3f18819 (both) | A |
| 13:53-13:58 | P178 | zip; bin-t5r | d72631aab936fc4e (both) | d77df25fc3f18819 (both) | A |
| 15:01-15:04 | P180 | bin-t5r3 (4 arms) | d72631aab936fc4e (all) | - | A |

- The two states split at character 233 at 4k ("doubly-linked list" vs "dictionary (for O(1) lookups)") and at
  character 1,262 at 32k ("Custom exceptions" vs "Custom Exceptions"). Within each block the hashes are stable.
- Notebook (10:34 CDT): "No input file changed (launcher 10-16 22:42, models 10-06, template no date, calib 03:10,
  det_answer / quick_tps old). Cause open (a rig state that changed between 05:15 and 10:28)." Notebook (12:33 CDT):
  "the rig drift flipped back (two numeric states; cause open)." #138 19:59:42Z lists it as open.
- Observation by this record writer (not tested): state B was seen only at 10:28-10:40, after P171 (a second
  llama-server with another model on the card, 08:06-09:06) and P173 (test-backend-ops perf, 10:26-10:27). No det_answer
  ran between 05:15 and 10:28 or between 10:40 and 12:07, so the times of the flips are not known.
- Effect on the records: P174 stopped at T5-0 (its gate used P169's hashes). P174b's T5 results are in state B; P175
  and later are in state A, so P175 S-1 cannot test bitwise equality with P174b (P176 does, in one block). From P174b
  on, every identity gate is in-block.

## E83 The pool reserve (PR1, PR2, PR #171) and the open G2 ask

| | |
| --- | --- |
| Date | PR1 plan 13:59:30Z; PR1 result 14:44:24Z; PR2 plan 14:45:15Z (comment 6235261102); PR2-b G1 + G3 PASS and the G2 ask 15:58:19Z (comment 6236213480); PR #171 opened 15:58:31Z; the queue question 17:09:59Z (comment 6237299307) |
| What (release / kernel sessions, 4070) | "CONFIRMED, the full-card prefill slowdown is the VMM pool growth": cold 16k P0 1,247.8 tok/s; ballast after /health 395.1 (3.2x slower); `GGML_CUDA_POOL_RESERVE_MIB=256` then the ballast 1,218.6 (-2.3 %). "The 2060's 2x / 10x slowdowns with small programs (P166 G4b, P167b) fit the same cause." PR2-b: the 8 GB preset reserves 176 MiB at start |
| G2 for the 2060 | "The launcher prints `pool reserved 176 MiB` in its 8gb line. Cold 128k within 2 % of P168 (239.2 tok/s), and trace min free not lower than P168's 86 MiB minus 16 ... Also 0 spill lines. A small ballast (free - 100) after `/health`, then a cold 16k read ... 0 CUDA errors." 17:09:59Z: "Is G2 for PR #171 ... in your queue? ... It is the last gate before #171 can merge. If T5 work comes first, just say where it sits." |
| State | Found by this record writer: no 2060 reply on #138 or PR #171 and no notebook entry about G2 in this range; P183 was queued next. PR #171 is open |
| Links | PR #171; P166; P167b; P168; issue #138 |

## E84 The filler time 13:10-13:47 and the filler preemption

| | |
| --- | --- |
| Date | Queue log: "13:10:31 done 69jebg-p176-skip-exact.sh", "13:10:31 queue empty - filler filler_b_lookup.sh", "13:46:35 filler filler_b_lookup.sh exit 0", "13:46:35 queue empty - filler filler_c_humaneval.sh", "13:46:57 filler filler_c_humaneval.sh exit 143", "13:46:57 run 69jebh-p177-chunk8k-crash.sh". Notebook 13:47 CDT: "GPU ran fillers 13:10-13:47 while I wrote code (my miss)." Notebook "16:02 CDT Fillers now yield to queued jobs (preempt_lib.sh)" |
| The miss | 36 min of filler work instead of experiments while the dense-layer option and the P177 split were written. The P177 queue file was written 13:46:38 (found by this record writer), so no job was pending in 13:10-13:46: the runner did not hold a job back; the job was late |
| The fix | Notebook 16:02 CDT: "The runner checks queue/pending only after a filler ends, so a job queued during a filler waited up to ~40 min (or I stopped the filler by hand ...). Each filler_*.sh now sources preempt_lib.sh: a watcher checks every 20 s and, on a pending job, logs "filler X preempted by Y", stops the filler's children, the server (stop.ps1) and the filler. The runner itself is unchanged (it runs as a long loop; editing it in place is unsafe)." |
| First use | "16:53:47 filler filler_b_lookup.sh preempted by 69jebn-p183-variance-128k.sh" (the P183 file was written 16:53:46) |
| Note | Preemption helps a job that is queued while a filler runs. It does not help when the next job is not yet written (the 13:10-13:46 case) |
| Links | scripts/preempt_lib.sh; scripts/filler_a_deep.sh, filler_b_lookup.sh, filler_c_humaneval.sh |

## E85 The T5 proposal and P183

| | |
| --- | --- |
| Date | T5 speed table 19:59:42Z (comment 6240053781; notebook 15:04 CDT "Posted the speed table on #138"); the proposal 21:54:09Z (comment 6241806079; notebook 16:53 CDT) |
| Speed table | "cold 245k 1,452 -> 713 s (2.04x), cold 128k ~532 -> 371 s (1.43x)", the mask / exact skip / capture guard / `dense=` parts, and the P174b / P175 / P178 rows |
| Proposal | "T5 window 32k passes the three 245k sets on the 2060 at 1.78x. Proposal: ship it as an opt-in fast cold read." n24 24/24 (814 s), code 19/24 (801 s), prose 9/24 (808 s); "Total: 52/72 against 54/72 for dense". The engine patch (fork `t5-window-emu`, HEAD d1cc7a4bd, off by default; "Dense ops never skip, so the default bits are unchanged"); a launcher switch `BONSAI_FAST_READ=1` that sets `LLAMA_PREFILL_WINDOW=window=32768,sink=1024,tail=1024` ("Only for `-np 1`: the dense-tail position is a process global today"); README limits (lossy on paraphrase-style questions; a conversation read in this mode keeps its windowed K/V; the gain depends on depth); 4070 gates (identity, n24 and the P170 sets on the 12 GB recipe, PPL / KL at 64k and 128k, a long agent soak) |
| P183 | Queued 16:53:46 (queue file 69jebn-p183-variance-128k.sh): "dense prose again + window-32k prose again (noise floor), 128k cold read + n24 at 128k with window 32k". Running at the time of writing |
| State | No decision on the proposal in this range |
| Links | P178; P181; P182; issue #138 |

## E86 Corrections in this range

- P169: the notebook and #138 say "18 lost items say the text has no such code"; the receipts show 15 such answers, 3
  answers cut at 40 characters (vaults 7, 11, 20) and 1 wrong code (vault 22). Found by this record writer.
- P169: the script's own T4-0 compare was empty vs empty (no `sha256sum` on the runner's PATH); the PASS rests on the
  det_answer hashes (notebook 05:17 CDT).
- P170: the answers in the receipts are at most 60 characters (the driver's record cap at run time; changed to 300 at
  08:02, after the run). The copy of `p170_drive.py` here is the 08:02 version. `p170_build.py`'s docstring says
  "#define macros"; the code inserts `static constexpr int` constants. Found by this record writer.
- P171: prose small item 20 is a false positive of the keyword grade ("does not contain any information about ...
  capelin"). By meaning prose small is 12/24 and 5 right where dense was wrong; the notebook (10:26 CDT) and #138
  (15:26:48Z) say 13/24 and 6. The kept reads hold up to 24,006 tokens, not 16,384 (the keep counts estimated tokens).
  The notebook's "~120 chunks" / "~87 selected chunks" are not in the receipts (chunks_kept 147-174 / 128-139, with the
  sinks and the window). Found by this record writer.
- P173: run.txt holds only the warm-up lines of the grep; the numbers are in perf_all.txt. The Turing int8 peak behind
  "~25 %" is not in the receipts. Found by this record writer.
- P174: T5-0 failed against P169's hashes because the product zip itself moved (E82), not because of T5; P174a split
  the two changed factors (bin-t5 and `BONSAI_SPARSE=0`). The 32k split is at character 1,262 (the notebook names only
  the 4k split at 233). Found by this record writer for the 32k split.
- "Dense 1,452 s" at 245k (P178 R-1, the #138 tables 19:59:42Z and 21:54:09Z, P182 "1.78x" on n24) is P174b's
  mask-only read (the same work as dense), not a dense run; the 2060 dense reference is ~1,489 s (16b, another build).
  Found by this record writer.
- P175 S-3: the script printed "S-3 chunk size " with no value (S-2's output was a traceback); the server ran the
  launcher default of 32,768 (server log), as the notebook says. The `cuda()` "chunk line" is empty in every arm. Found
  by this record writer.
- P176: the cold times named in the script header are not in the receipts; the server logs give A 532.5 s, B 483.1 s,
  C 532.8 s at 128k. Found by this record writer.
- P180 at 4k shows that the dense-mask path no longer breaks the output, not that the dense layers work at depth (P181
  does). Found by this record writer.
- P181: "Lost in every arm: 7 (heron), 9 (g7), 22 (spruce)" is not true for P178 R-4 (window 32k), which has item 7
  right. Found by this record writer.
- #138 21:54:09Z: "Fork `t5-window-emu`, 5 commits on the bundle-20261017 engine" lists 4 parts; the branch has 6
  commits on 96f6e49cd (E81; fd17c67db was later fixed by d1cc7a4bd). Found by this record writer.
- E84: the 13:10-13:47 filler time was not a job held back by the runner: the P177 file was written 13:46:38. Found by
  this record writer.
- E83: the G2 ask for PR #171 has no 2060 reply in this range. Found by this record writer.
- Notebook headings in this range: the request for these records says that some headings had run ahead of the clock and
  were corrected in the notebook before this record was written. This record writer checked every heading of the range
  against queue.log, build_ahead.log, the queue-file times and the GitHub times: all now agree; the "05:53 CDT" entry is
  8 min after its post (10:45:05Z). The earlier heading text is not available to this record writer.

## E87 Lessons recorded in this range

- P174 / E82: run every identity gate in-block (product bins then test bins, back to back); a hash from hours before
  can belong to another numeric state of the rig.
- P174b: add an engagement control (a small change must change the bytes) to every mask or emulation gate.
- P177 / P179: a host sync (cudaMemcpyAsync to pageable memory + cudaStreamSynchronize) is illegal inside CUDA graph
  capture; check `cudaStreamIsCapturing`. A second context (the MTP draft) can reach the same op under capture.
- P178 R-3 / P180: test a new mask path first at a depth where it must change nothing; in a hybrid model, fill every
  mask in the hybrid memory input.
- P171: check graded-right answers for denial words before a keyword score is posted.
- P170 / P169: record enough of each answer to grade its content.
- P175 S-3: a queue step that uses a value parsed from an earlier step must check that the parse worked.
- E84: fillers yield to a queued job within 20 s (preempt_lib.sh); write the next job before the current one ends.
- TOOLBOX (section 10): the `${VAR//pattern/repl}` backslash trap through inline shell commands; Python `"\b"` and
  printf escapes in Windows paths; write such scripts with a file write and scan the bytes.
