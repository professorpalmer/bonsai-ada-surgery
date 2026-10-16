# Events, 2026-10-14 to 2026-10-16 (range p133-p155)

Notebook entries in this range that are not experiments: releases, PRs, issue threads, decisions, incidents and
lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-14 06:52Z kernel-session lead:
ranking, not budget ..." to the end (entry "2026-10-16 08:10 CDT T1-c v2 ..."), receipts/queue.log, the receipts
named below, and the PR list of this repo (titles and merge times). Numbering continues from `events-p109-p132.md`
(E23-E37). Times with "Z" are UTC (GitHub, notebook headings); "CDT" and other times are rig local time (UTC-5). The
GitHub posts of both sessions use the same account; "4070" and "2060" name the session.

- [E38 Windows Update restart and NVIDIA driver 610.88](#e38-windows-update-restart-and-nvidia-driver-61088)
- [E39 The 4070's overnight decisions: NORM out, FRAC budget, sparse opt-in, the RC](#e39-the-4070s-overnight-decisions-norm-out-frac-budget-sparse-opt-in-the-rc)
- [E40 R04 and R04b, and launcher #49 3035572](#e40-r04-and-r04b-and-launcher-49-3035572)
- [E41 D26a and the 64k line step](#e41-d26a-and-the-64k-line-step)
- [E42 bundle-20261014 (patch 0055) and its 2060 checks](#e42-bundle-20261014-patch-0055-and-its-2060-checks)
- [E43 The q3_0 set before its runs, the 0056 rule and release-20261014b](#e43-the-q3_0-set-before-its-runs-the-0056-rule-and-release-20261014b)
- [E44 R10 and PR #95: FRAC 1/8 for BONSAI_SPARSE=1](#e44-r10-and-pr-95-frac-18-for-bonsai_sparse1)
- [E45 Issue #21 archived and closed; issue #105 opened](#e45-issue-21-archived-and-closed-issue-105-opened)
- [E46 bundle-20261015, the launcher bug (PR #108) and bundle-20261015b](#e46-bundle-20261015-the-launcher-bug-pr-108-and-bundle-20261015b)
- [E47 P132 stopped; Cary: the card items first](#e47-p132-stopped-cary-the-card-items-first)
- [E48 D26g fails; Cary: the card waits for D26h](#e48-d26g-fails-cary-the-card-waits-for-d26h)
- [E49 The missed D26h posts, the fillers and bundle-20261015c](#e49-the-missed-d26h-posts-the-fillers-and-bundle-20261015c)
- [E50 The P146 false starts](#e50-the-p146-false-starts)
- [E51 D26h passes on the 2060; patch 0059 and release-20261016](#e51-d26h-passes-on-the-2060-patch-0059-and-release-20261016)
- [E52 bundle-20261016 and the 8 GB card (PR #142)](#e52-bundle-20261016-and-the-8-gb-card-pr-142)
- [E53 Deep-context research: issue #138 and the cold read-in plan](#e53-deep-context-research-issue-138-and-the-cold-read-in-plan)
- [E54 T1: slot save / restore and the layer cache](#e54-t1-slot-save--restore-and-the-layer-cache)
- [E55 Corrections in this range](#e55-corrections-in-this-range)
- [E56 Lessons recorded in this range](#e56-lessons-recorded-in-this-range)

## E38 Windows Update restart and NVIDIA driver 610.88

| | |
| --- | --- |
| Date | 2026-10-14 02:29-02:36 (rig time); notebook entry "02:29 Windows Update restart + NEW NVIDIA DRIVER 610.88 (was 591.86); P124 partial; P134 (driver baseline)" |
| Event log | 02:29:09 MoUsoCoreWorker planned restart (Service pack); 02:29:16-02:30:21 WindowsUpdateClient installed "NVIDIA Display Driver Update (32.0.16.1088)" = 610.88; 02:32:57 and 02:33:28 TrustedInstaller planned restarts (Upgrade); 02:36:12 KB5127648 (26200.9711) installed. Clean shutdowns (no 41 / 1001 / 6008). Boot 02:33:51. Fan back to 41 % -> slot 5 |
| Run cut | P124 (3ab0af3c2, launcher c1908b7 defaults, 591.86), partial: def sweep 4k 52.8 / 32k 47.4 / 64k 35.2 / 96k 27.0 / 128k 26.0, min free 171; deep_def 160k 20.2, 245k 14.4, trace min free 43 MiB at 02:04:21 (gate 60: FAIL, "the f16-bounds reserve is NOT spare at 245k"); deep_off 160k 10.6, 245k not reached. Not rerun (superseded by the int8 build). Script -> done/*.partial-restart |
| Follow-up | P134 (queue 69ic3, first): op tests + P126b's same-session 1011 vs 1013 sweep on 610.88. Result: driver neutral; the spread follows the line. "All later runs are on 610.88; cross-driver comparisons are not valid" |
| Open for Cary | Pause Windows Update / block driver updates during runs (a system setting; not done by the agent) |
| Links | P124; P134; E34 |

## E39 The 4070's overnight decisions: NORM out, FRAC budget, sparse opt-in, the RC

| | |
| --- | --- |
| Date | Notebook entries "06:52Z kernel-session lead: ranking, not budget -> P133 gets a NORM arm; P127 builds 8d6e0d3f4" and "~07:15 (local) the 4070's overnight decisions: FRAC budget, opt-in sparse; R06 plan on the RC" (#21 / #56 08:55Z, 11:47Z, 12:12Z) |
| NORM lead (06:52Z) | 8d6e0d3f4 (product-sparse) = c8bbb1898 + GGML_CUDA_FA_SPARSE_NORM=1 (rank pages by each Q head's bound relative to that head's best page; off by default; one file, fattn.cu). P127 builds it; P133 gets a fourth arm (B 8192 + NORM) |
| 4070 answers | D22c at 245k: B 8192 9/10 (_convert_other), 12288 and 16384 10/10, dense 10/10. D23 NORM at B 8192 9/10 (the same miss) -> NORM out. Budget = max(B, host tail x GGML_CUDA_FA_SPARSE_FRAC 1/16). RC: product-0055 4de618549 |
| Headroom | 11:47Z: the 43 MiB at 245k (P124): the launcher may miss ~20 MiB; the 4070 measures (R05 peak VRAM); final headroom in #49 |
| Decision (12:12Z) | Option 1: sparse opt-in BONSAI_SPARSE=1, default off (#49 d927d6b); D26 (bounds without a line cost) next. This follows P127 (int8 bounds still -8.1 % at 64k; the 5 % default rule not met) |
| R06 gates (docs/research/release-20261014) | SHA, op tests, 4k-128k within 3 % of bundle-20261013 same session, 160k / 245k >= 1.8x, 245k copies / needles = dense, fresh 60k, 0 one-token, min free >= 60, HumanEval on the bundle bins |
| Queue changes | P128, P133 (8d6e0d3f4) and P125 (3ab0af3c2) superseded -> done/*.superseded. New: P135 (69ic4: build RC 4de618549 in prism-tiergraphs product-0055-rc-2060 -> bin-rc55, op tests, 160k -> 245k dense vs BONSAI_SPARSE=1, launcher test copy start-server-rc55.ps1 = #49 d927d6b + BONSAI_BIN); P136 (69ic5: copies / needles at 245k and 200k). P120 -> bin-rc55 + BONSAI_SPARSE=1 (third change before it ran). Order: P134 -> P135 -> P136 -> P129-P132 -> P119 -> P120 |
| Links | P127; P128; P133; P135; P136; E35; E40 |

## E40 R04 and R04b, and launcher #49 3035572

| | |
| --- | --- |
| Date | Notebook entries "4070 R04 FAIL at 200k ...", "13:16Z #49 3035572 (4070) ..." and "14:04Z PR #67 (4070): R04b ..." |
| R04 (4070) | RC 4de618549, FRAC 1/16 (~10.4k cells, keeps 162 of 2604 pages) at 200k: miss _pydatetime _check_tzname (0.15); publish stopped; R04b (dense 200k, 12288 floor) queued there. P136 got a third arm before the run (BONSAI_SPARSE=1 + GGML_CUDA_FA_SPARSE=12288,64,1024; order 200k then 245k) |
| #49 3035572 | Sparse headroom 36 -> 64 MiB (245k trace: sparse - dense 150 MiB vs 138 counted, +16 margin); BONSAI_SPARSE=1 sets floor B 12288 (engine max(B, tail/16)); the 160k gate for opt-in now >= 1.5x (245k stays 1.8x) |
| Swap during P135 | start-server-rc55.ps1 was swapped to 3035572 at ~08:25 while P135 ran its dense arm (unaffected: sparse off); P135's sparse arm used 3035572; P135's header still names d927d6b (not edited while running) |
| P136 rewritten | Before the run: dense vs BONSAI_SPARSE=1 at 200k, 245k, 160k (12 fresh servers); the 12288 floor is now the launcher's |
| R04b (PR #67) | Dense at 200k misses the same item sparse missed (_check_tzname): the model's own miss. R04 amended before R04d: "sparse not below dense on the same items"; floor decision rule declared before R04d |
| Links | P135; P136; E39 |

## E41 D26a and the 64k line step

| | |
| --- | --- |
| Date | 2026-10-14 17:25Z (notebook "D26a (4070): 64k sparse cost = the line ..."); P137 result entry |
| D26a (4070, PCIe 4.0) | Engine overhead +0.2 %, line cost +2.6 % |
| P137 (2060) | off_short (pinned 52,224) 35.4 / 35.4; on_short 35.5 / 35.4 (0 sparse ops); off_long (61,696) 36.4 / 36.3: overhead +0.1 %, line cost -2.6 % = the 4070's |
| Reading | P123 / P127's -7 / -8 % came from off arms at 61.7k-63.5k serving 64k with ~no host tail: "the 64k cost on Turing is mostly a step (any host tail vs none), small slope after. For D26: bounds must not take line from the no-tail range (staging span idea), a smaller reserve alone does not help" |
| Links | P123; P127; P137; E48; E51 |

## E42 bundle-20261014 (patch 0055) and its 2060 checks

| | |
| --- | --- |
| Date | 4070 all release gates pass 19:37Z (R01-R05 + amendments; 2060 P135 / P136); #56 (0055) merged, then #49; README note #77. Published 19:40Z (14:40 rig time) |
| Release | Patch 0055 sparse opt-in. Zip c91dfc98...4cd0, 611,390,390 B; release commit bfae9143; engine 4de6185494 sm 75/86/89 |
| PR #75 | Merged 18:41Z: pool off with -md; reviewed from 8 GB: MTP default unchanged, PoolMiB follows $PoolOn |
| 2060 checks | P138 (default switches): sha / tests / commit; same-session A/B vs 1013 -0.8 / -0.2 / -0.6 %; PASS. P139 (zip bins): 245k sparse 2.19x, min free 153, copies / needles = dense, HumanEval 158; PASS. Launcher test copy start-server-1014test.ps1 = bfae9143 start-server.ps1 + BONSAI_BIN (= rc55 launcher + #75 only, diffed). R08 (PR #89) and R09 (PR #92) on the 4070 side |
| Links | P135; P136; P138; P139; E39; E40 |

## E43 The q3_0 set before its runs, the 0056 rule and release-20261014b

| | |
| --- | --- |
| Date | 2026-10-14 18:41Z-22:33Z; PR #101 (S04 + S05 pass) 2026-10-15 11:19Z |
| Engine switches before the runs | The 2060 q3 set (P129-P132, not started) moved three times: to q3-on-0055 7c7b47e156 (PR #76, Q07; launcher copy start-server-sparsetest2q3.ps1 rebuilt from start-server-rc55.ps1 + 'q3_0' { 14336 }; P132 arms set BONSAI_SPARSE=1); to q3-fast df218650a (D27 PASS 20:44Z: half2 tile dequant, bit-exact, 64k q3 -1.6 % vs q4_0 on the 4070); to product-0056 b86298dba (PR #88: 0056 + 0057; D28 PASS: q4 +0.6 %, q8 +0.8 % on the 4070, byte-identical). Headers noted each time |
| 0056 default rule (PR #84, 20:18Z) | q3_0 is the 8 GB default only if (1) 64k decode within 5 % of q4_0 (same session, alternated), (2) PPL 16k <= +1 %, (3) HumanEval >= 157, (4) copies / needles = q4_0. Else opt-in BONSAI_CTK=q3_0. PR #83 merged: launcher q3_0 cell size 14,336 on main |
| Gates PR #86 (20:47Z) | S04 (the q3_0 default rule on the 0057 build) and S05 (q4_0 default unchanged: same answers as bundle-20261014, <= 2 % slower at 64k / 128k). S05 = P140 |
| 2060 results | P129: PPL 16k q3_0 +0.56 %, identical to P108 to 4 decimals. P130: 64k q3 41.0 / 41.0 vs q4 39.6 / 39.6 (+3.5 %); 160k copies / needles equal; line 61,696 -> 80,640 (1.31x). P140: S05 PASS (+11.2 % at 64k for q4_0 with 0057). P131: HumanEval q3_0 163/164 (fail 93). S04 all four items PASS: q3_0 = the 8 GB default by rule |
| 4070 | PR #90: S01-S03 PASS (22:33Z). 11:37Z: all release-20261014b gates pass; merging #88 then #91 (q3_0 8 GB default) |
| Links | P129-P132 (records plan only, results in the notebook); P140; E46 |

## E44 R10 and PR #95: FRAC 1/8 for BONSAI_SPARSE=1

| | |
| --- | --- |
| Date | PR #93 (R10 plan) 03:57Z; R10 partial 04:30Z; R10 complete 04:45Z (PR #96); R10b PR #97 05:26Z; #95 rule amended PR #99 05:27Z; PR #98 (bench lenient score) 05:28Z; #95 merged 10:29Z; R11 = P141 (PR #100) |
| R10 (4070) | Wider items for the shipped rule (Mirai S missed a needle digit at 0.958 with FRAC 1/16 + 12288 floor): 245k code_needle n 20 / needle_depth n 24. Result FAIL: FRAC 1/16 loses copy _check_tzname (0.128), vault 13 (0.521), vault 15 (0.604) that dense gets right (dense 20/20 + 23/24; vault 14 wrong in dense, right in sparse) |
| R10b (4070) | FRAC 1/8 = dense in substance on their set |
| #95 rule (amended before P141) | Merge if P141's FRAC 1/8 arm (a) is not below FRAC 1/16 on any item of the 2060 set, (b) not below dense on any item in the droppable host tail, (c) >= 1.5x dense at 160k and 245k. Reason: R10b's strict miss (_check_tzname, cells 30,772-30,823) is inside the VRAM line; the answer has the exact body + the real comment above it |
| 2060 (P141) | dense 20/20 + 24/24; 1/16 20/20 + 23/24; 1/8 20/20 + 24/24; 1/8 1.59x / 1.76x: rule PASS |
| Merged | #95: FRAC 1/8 for BONSAI_SPARSE=1, the summary prints the budget, depth-trade text ~1.6x / ~1.8x |
| Process fix | The 4070 asked for status at 09:47Z during P141 (no partial posted for ~5 h): partial lines on runs > 3 h |
| Links | P141; E42 |

## E45 Issue #21 archived and closed; issue #105 opened

| | |
| --- | --- |
| Date | PR #94 merged 2026-10-15 04:07Z; #105 opened 11:44Z; #21 closed after P145 (11:52 CDT) |
| #21 archive | docs/research/issue21-20261010/ (18 decisions + verbatim thread). Agreed: close #21 after the 0056 bundle ships and P141 is in; a new issue for the next phase (D26) |
| #105 | Successor of #21: D26 sparse default-on. Step 1 D26g (2060, data only): with q3_0 the line is 80,640 and the reserve ~6.6k q3_0 cells (sparse line ~74k), so 64k stays in VRAM in both arms. Gate (declared in #105 before the runs): no depth <= 128k loses > 2 % (sparse vs off), 160k / 245k gains stand. If pass: launcher-only change BONSAI_SPARSE default 1 on 8 GB. Step 2 (late reserve, engine) only if it fails in ~74k-110k. P143 = D26g |
| Links | P141; P143; P145 |

## E46 bundle-20261015, the launcher bug (PR #108) and bundle-20261015b

| | |
| --- | --- |
| Date | bundle-20261015 published 11:40Z; P142 06:59-08:15 CDT; PR #108 merged 13:25:17Z; bundle-20261015b published 13:28Z (PR #109 README note, PR #110 HF card, PR #111 S06b) |
| bundle-20261015 | 0056 q3_0 + 0057 packed-half; q3_0 8 GB default; BONSAI_SPARSE=1 budget 1/8. Zip 616,638,283 B, sha256 23db0bc477274314e817f3eaeda185b9ac314f31d346f45fc4861b2e3ae7dd16; engine b86298dba9; launcher = release commit 0cbd0dcc. P119 / P120 changed before their runs to bundle-20261015 default / + BONSAI_SPARSE=1 (launcher 1015test) |
| The bug (found by P142) | Every arm printed "window 262144 / q4_0", line 61,696. start-server.ps1 line 108 `$HasQ3 = $Help -match '<0x08>q3_0<0x08>'`: backspace bytes for backslash-b (bytes 27 08 71 33 5f 30 08 27). Probe in the serve.ps1 way: -match 'q3_0' True, HasQ3 False, Ctk q4_0; fixed: HasQ3 True, Ctk q3_0. "Same class as the rig's own inline-bash backslash loss (my first fix attempt wrote 0x08 back; fixed via chr(92) script)" |
| Repo scan | README.md had "layer<0x0C>etch_runtime.ps1" twice (form feed for backslash-f), fixed in the same PR #108; a NUL in an artifacts data file left alone |
| PR #108 (4070 review) | The backspaces came with the final #91 revision; the fixed pattern matches 0056 --help, not 0055; the README form feed came from the first commit |
| P143 under the bug | First start 08:15 (q4_0 by the bug) stopped -> receipts/p143-q4-launcherbug; queue log NOTE 08:20; restarted 08:20 with the fixed test copy (q3_0, line 80,640 in its log). P143 / P144 use the same engine bins + the fixed launcher copy = the 15b setup |
| bundle-20261015b | Zip 616,638,401 B, sha256 a6bf7add...5776, release commit 444de56. P145 (queue 69ia15, after P143, before P144): the zip's own start-server.ps1 (control-byte check + test copy with BONSAI_BIN), q3_0 default, sweep vs P130, fresh 60k: PASS |
| New gate | From P145 on, every post-zip check scans the zip's start-server.ps1 for control bytes (P145, P147, P150: 0) |
| Links | P142; P143; P145; E43 |

## E47 P132 stopped; Cary: the card items first

| | |
| --- | --- |
| Date | 2026-10-15 06:58 (notebook "P132 stopped (partial: sparse + q4_0 at 160k 17.7, 245k not reached) ...") |
| P132 | Stopped as partial: sparse + q4_0 at 160k 17.7, 245k not reached; "not needed for the card (FRAC 1/16, old launcher)". Script -> done/69ik-p132-q3sparse-deep.sh.stopped-partial. P132's record stays "plan only" (index-p116-p132) |
| Decision (Cary) | "the card items are top priority" |
| Queue | P144 (queue 69ia2, gate in its header): 245k copies n 20 / needles n 24, dense vs BONSAI_SPARSE=1 on the bundle-20261015 zip with its launcher defaults (q3_0) = the shipped-setup quality receipt. Order: P142 (running 06:59) -> P143 (D26g) -> P144 -> P119 -> P120 |
| Links | P132; P142; P143; P144 |

## E48 D26g fails; Cary: the card waits for D26h

| | |
| --- | --- |
| Date | D26g-pre on the 4070 12:17Z (PR #107); P143 partial 10:35 CDT; Cary 10:45 CDT; P143 result 11:27 CDT |
| D26g-pre (4070) | q3_0, lines pinned to the 2060's 80,640 / 73,984: 64k 0.0 %, 80k -30.7 % (line step), 96k +3.5 %, 112k -16.1 %, 128k -19.1 % (sparse engages at MIN_HOST 32,768 and is slower than dense with prefetch on PCIe 4.0). Plan D26h (after P143): late reserve (removes the line step) + a self-timing engage rule (alternate dense / sparse blocks, keep the faster per 16k host-tail band, decision fixed per band for determinism). P143 got arm sp_mh64k (MIN_HOST 65536) before the run. "Realistic: sparse default-on = engine work (D26h), days" |
| P143 (2060) | FAIL: 80k -6.7 %, 96k -3.0 %, 112k -18.5 %; deep 1.34x / 1.44x on q3_0. "Decision: default-on is not shippable as built; it supports D26h (late reserve). Card wording "one switch" unless D26h passes" |
| Decision (Cary, 10:45 CDT) | "willing to wait... i want to deliver the best possible product". No "one switch" interim card. The card waits for D26h (late page-bound reserve + self-timing engage) to pass the #105 gate on the 2060, plus the P143 deep pair, P145 and P144. The 2060 asked the 4070 to put D26h first (#105) |
| Links | P137; P143; P146; E41; E51 |

## E49 The missed D26h posts, the fillers and bundle-20261015c

| | |
| --- | --- |
| Date | 2026-10-15; notebook entry "18:35 CDT D26h on the 2060: ..." |
| What happened | "Missed the 4070's D26h posts (16:56Z-20:22Z) for ~3 h: the queue ran fillers (lookup, HumanEval, deep) after P144, so the GPU was not idle but the top-prio item waited." After P144 the queue ran P119 (14:05-14:57) and P120 (14:57-15:43), then fillers C, A, B, C, A from 15:43 to 18:34 (queue log) |
| Fix | filler_a_deep stopped by hand at 18:34 (queue log: "filler_a_deep stopped by hand for P147 / P146 (top prio)") |
| Build | vendor/prism-q3kv detached at ab9481005 (product-0059; was product-0056-2060 b86298dba), build-q3kv incremental 18:31-18:33 exit 0 -> tooling/bin-d26h (old bins kept in tooling/bin-b86298dba-keep). The DLL has GGML_CUDA_FA_SPARSE_AUTO / KV_TIER_DEMOTE_FRAC / FA_SPARSE_CALIB. Launcher: #126 launcher-late-reserve 7f16808 -> start-server-d26htest.ps1 (+ BONSAI_BIN line, 0 control bytes) |
| bundle-20261015c | Asked on #105 16:56Z: new llama-server with patch 0058 (PR #113, Responses API tool output with an image) and 3 rebuilt ggml DLLs; zip 616,639,105 B; README note PR #114, HF card PR #116, S07 PR #117. P147 (18:34-18:54): PASS |
| Links | P144; P146; P147 |

## E50 The P146 false starts

| | |
| --- | --- |
| Date | 2026-10-15 18:54-19:08 (queue log); notebook entry "19:10 CDT P146 restarts (two false starts, no data)" |
| Try 1 (19:02) | tooling/bin-d26h had no CUDA runtime DLLs: the launcher help probe failed (window 131072 / q4_0) and the server did not start. Receipts: receipts/p146-try1-nodlls (setup.txt, auto_r1.*, off_r1.*). Queue log 19:08:03 FAILED. Fix: bin-d26h = build + cublas64_13 / cublasLt64_13 / cudart64_13 / nvJitLink_130_0 / nvvm64_40_0 from bin-q3sparse (--version commit ab9481005) |
| Try 2 (19:08:17) | "a sed edit replaced the running file, but bash had the old one open (old BIN): stopped." Queue log 19:08:33 FAILED; filler_b_lookup stopped by hand. Try 3 = queue 69jb, 19:08:34 |
| Race | "A cleanup rm of receipts/p146 raced the try-3 start: folder + setup header re-made by hand; op-test lines may be missing (try 1: 3115 / 123 / 177 pass)" |
| Lesson (notebook) | "copy a test bin from an existing bin-* folder (it has the CUDA DLLs); never edit a queue script in place while it runs" |
| Links | P146 |

## E51 D26h passes on the 2060; patch 0059 and release-20261016

| | |
| --- | --- |
| Date | P146 result 23:39 CDT; 4070 00:00 CDT; PR #125 / #126 merged 2026-10-16 04:44Z; P148 result 02:56 CDT; release-20261016 plan PR #131 (04:46Z), gates PR #133 (06:29Z), published PR #137 (08:06Z) |
| P146 | PASS G1-G4 (r2 auto / off: worst -1.5 % at 112k; 160k +2.6 %, 245k +10.1 %; det answers identical; min free >= 71 MiB). Findings posted on #105: FRAC 1/4 keeps only +10 % at 245k vs P143's 1.44x at 1/8; the calib key holds the exact line and the line moves 512 cells between launches, so r2 re-timed all bands |
| P148 queue note (19:35 CDT) | "the engine line "GGML_CUDA_FA_SPARSE needs an f16 mask (LLAMA_ARG_KQ_MASK_PACKED=0); off" appears once early in P146 auto_r1 AND in P143 sp_r1, where sparse then ran (keeps 192 of 655 pages): not a fault." 4070: one combined release (D26 + D29 12 GB q4_0) waits for P146 + P148 |
| 4070 (00:00 CDT) | P146 = the merge gate (after the calib-key line rounding); release cut after P148. P149 queued (1/8 forced, n28 first, then n24 + code), not blocking |
| P148 | PASS: auto = dense item by item at 245k (code 20/20; n24 23/24; n28 27/28; the same misses). "The 2060 has no open item for release-20261016" |
| P149 part 1 | FRAC 1/8 forced, n28 at 245k = 27/28, miss vault 15 only (= P148 dense); vault 16 correct on the 2060; "Rigs disagree (4070 lost 16 at 1/8)". P149 stopped after n28 by plan; P149b pending |
| D30 (4070) | Adaptive page budget (floor 1/8 + up to 1/4 within DELTA logits) running at 04:10 CDT; "a budget change needs a pass on both rigs". PR #141 "research: D30 adaptive sparse page budget (closed)" |
| Links | P146; P148; P149; P150; E48 |

## E52 bundle-20261016 and the 8 GB card (PR #142)

| | |
| --- | --- |
| Date | P150 03:28-04:34 CDT; PR #142 merged 2026-10-16 09:36:10Z; notebook entry "04:55 CDT P150 result: bundle-20261016 PASS on the 2060; card merged (#142)" |
| Release | bundle-20261016: 8 GB q3_0 + automatic sparse (patch 0059). Zip 616,653,192 B, sha256 24343fd9...66dc, engine ab94810051, launcher fed8ae2d |
| P150 | sha match; ab94810051; FA / GET_ROWS / SET_ROWS pass; zip launcher q3_0 + auto, line 80,384; sweep 54.0 / 41.1 / 22.3 / 16.7 / 9.8 at 4k / 64k / 128k / 160k / 245k; cold 245k 1,696 s; 0 one-token; min free 71: PASS |
| The card | PR #142 "docs: 8 GB card for bundle-20261016", merged f6b2f86. Headline "128k now runs faster than 64k did"; honest note "cold read-in not faster yet". The notebook TODO of 2026-10-11 (Cary: the "8 GB, one week" before/after card, "when sparse / tier-graphs / q3_0 land") asked for this card; on 10-15 it waited for D26h (E48). The notebook does not mark the TODO as done |
| Links | P143; P144; P146; P148; P150; E48 |

## E53 Deep-context research: issue #138 and the cold read-in plan

| | |
| --- | --- |
| Date | Notebook entries "03:20 CDT Deep-context research (Cary: "28 min at max context is unusable", "card says set 131k")", "03:55 CDT Cold read-in plan posted on #138 (Cary: "useless in current form")", "04:10 CDT P154 queued (T2a, #138) ..." |
| Issue #138 | Opened with levers 1-7: disk prefix cache; block-sparse prefill; per-layer sparse budgets; FA kernel; prefill matmul; depth-gated tail 2; trained cache eviction. Fit: cold 245k ~35 % fixed (~590 s) / ~65 % attention (~1,100 s); decode 245k ~95 % PCIe. Cold 128k = ~595 s (P143 sp_mh64k ttft) |
| Cold read-in plan (03:55 CDT) | Floor: fixed work ~2.4 ms/token (64k ~154 s, 128k ~310 s, 245k ~590 s) even with free attention; ub 1024 did not help (P22 / P26). Tracks: T1 disk prefix cache + pre-read (2060), T2 exact kernels (4070), T3 sparse prefill attention, T4 token selection (early layers or a small Bonsai 2 scorer; the only track under the floor; opt-in first) |
| Queue | P151 (245k op-time profile, zip bins) and P152 (BONSAI_CTX 131k vs 262k at 4k-128k) after P150; P149b after them. P154 (T2a: t2-prefill 2724a8349 NCOLS2=2). Order (04:10 CDT): P150 -> P154 -> P151 -> P152 -> P149b; P153 (69jea5) and P155 (69jea6) were added later and sort before P152 |
| Results | P154: T2a exact on sm_75, cold TTFT 1.067x at 64k, 1.110x at 128k (4070 rule >= 10 %: met at 128k only; PR #146 "T2a cause corrected, P154, T2a-2 plan"). P151: time-weighted FA 65.3 %, MUL_MAT 25.2 %, GDN 4.1 %, other 5.4 %; "Floor confirmed (~10 min at 245k with free attention)" |
| Links | P151; P152; P154; `../coldread-20261016/` (PR #144) |

## E54 T1: slot save / restore and the layer cache

| | |
| --- | --- |
| Date | Notebook entries "06:15 CDT T1 (4070 T1-b PASS ...)", "06:45 CDT T1-c design posted on #138 (layer SlotCache) ...", "07:15 CDT T1-c built ..."; PR #145 (launcher BONSAI_SLOT_SAVE_PATH) merged 11:06Z |
| T1-b (4070) | Restore + continue at 245k in 2.2 s vs 468 s cold, byte-identical |
| 2060 side | Server + launcher: branch launcher-slot-save-path (BONSAI_SLOT_SAVE_PATH -> --slot-save-path; PR #145). P153 (69jea5): T1-b on the 2060 + a thinking-on pair at 64k. Result (receipts): restore + prompt 1.85 / 2.75 / 5.23 s at 64k / 131k / 245k, answers equal; with thinking on the restore does not help (full re-read) |
| T1-c design (06:45 CDT, #138) | Layer SlotCache: tokens via /apply-template + /tokenize; save at the END OF THE PROMPT (prefill-only call + save) so the next turn always extends it; restore the longest saved token prefix on mismatch; LRU disk budget 20 GB; gates E1 restart, E2 switching, E3 edited history, short prompts unchanged |
| T1-c build (07:15 CDT) | Branch layer-slot-cache: layer/slot_cache.py + 4 hooks in bonsai_layer.py; offline test vs a fake server passes (save, continue, restart-restore, short skip, switching). "Bug found before any run: the first hook ran before the layer adds run_python to the tools, so the tokens would not match: moved to the send points." P155 (69jea6, after P153): gates E1 / E3 / S + thinking-on pair, layer run with the sandbox stubbed (no wasmtime on this rig). Running from 07:24:56 |
| P153 result (07:40 CDT) | "G1-G4 PASS thinking off: restore + continue 64k 1.85 s, 128k 2.75 s, 245k 5.23 s (cold 1,689 s); files 1,049 / 1,938 / 3,492 MiB; B2 == D2. Thinking on 64k: in memory 117 tokens (RAM checkpoint), after restore 65,722 (full re-read): confirms the save-at-prompt-end design. Posted on #138." |
| T1-c v2 (08:10 CDT) | 4070 review (11:33Z): save before the generation prompt; take the saved count from the server's n_saved. layer_v2 built, offline test pass; P155b queued (69jea7) with extra gates (n_saved == the prefill token count; prompt_n after a restore <= new tokens + the generation prompt + 512; the thinking-on pair gated). Also queued: P156 = T2a-2 (Q1 PPL / KL 4k + 16k, Q3 cold 245k pair, Q2 items; outside this range). T1-d (read ahead: prefill_only request) design and a T3 ask posted on #138 |
| Links | P153; P155; E53 |

## E55 Corrections in this range

- P143 partial (10:35 CDT): the sparse line 80,640 -> 68,608 and "host tail under MIN_HOST 65536 from 68.6k to
  ~134k" were sp_mh64k values. The main sparse arms ran MIN_HOST 32768, line 80,640 -> 69,120 (sp_r2 80,128 ->
  68,608). Corrected in the 11:27 CDT entry; the #105 partial post was edited.
- P135: the header names launcher d927d6b; the sparse arm ran on 3035572 (13:16Z entry). Not edited while it ran.
- P138: the summary grep printed "gdn skip lines: ...:0" (quoting; the line is in the log) and the bin-hash step
  printed nothing (hashes computed by hand).
- P142: the rig's first fix attempt for the launcher pattern wrote 0x08 back; fixed with a chr(92) script.
- P146: try-3 op-test lines may be missing (a cleanup rm raced the start); try 1 had passed 3115 / 123 / 177.
- P140: the header names lookup_ab with 22 items; the depth-0 compare used 11 items per run.
- P153: the notebook names the middle depth "128k"; the run used 131,072 tokens.
- P155b (notebook 08:10 CDT): "a backspace byte got into a P155b comment line (C:<BS>onsai) from a Python escape;
  fixed with bytes; ctrl 0." The same class as the P142 launcher bug. (This record writer hit it once too, in a
  draft of P155.md, and fixed it with chr(92) before the commit.)
- Found by this record writer: P147's header expected the D26h build to run during P147; it had ended at 18:33 (the
  notebook says so in the result entry).

## E56 Lessons recorded in this range

- E38 / P134: after a driver change, rerun one same-session A/B on the same binaries; on this card decode past the
  line follows the VRAM line, and the line moves with idle VRAM after a reboot.
- P137 / E41: split a fixed cost with a pinned-line control arm; on Turing the sparse cost at 64k is a step (any host
  tail vs none), not engine overhead.
- P141 / E44: post partial lines on runs longer than 3 h (the 4070 waited ~5 h for P141).
- P142 / E46: scan shipped text files for control bytes (0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F); `\b` and `\f` that pass
  through a tool that eats backslashes become 0x08 / 0x0C. A release check must assert the launcher's chosen settings
  (K type, line), not only speed and tests.
- P143 / E48: a default-on gate must step through the band between the sparse line and the engage point; 64k / 128k
  alone read -0.9 % / -0.2 % and missed -18.5 % at 112k.
- E49: fillers can keep the GPU busy while a top-priority item waits; watch the GitHub threads during filler runs and
  stop a filler by hand for a top-priority job.
- E50 / P146: copy a test bin from an existing bin-* folder (CUDA runtime DLLs); never edit a queue script in place
  while it runs (bash reads the open file).
- P146: a calibration key that holds a value which moves between launches (the VRAM line, +-512 cells) defeats the
  cache; round it (the 4070's fix: "line_~81920/69632" in P150).
- P148: gate a quality test of a self-choosing feature on the log showing that it engaged; plan a forced arm for the
  other case.
- P153 / E54: a saved slot helps only if the next prompt starts with exactly the saved tokens; save at the end of the
  prompt, not after the reply (templates drop the reasoning from the history).
- P149 / E51: a page-budget change needs the same item test on both rigs; one rig's single miss can be card-specific.
- P142 / P155b: write a backslash in generated text with chr(92) or bytes, then scan the file for control bytes; on the
  rig, inline bash and Python escapes turned `\b` into 0x08 in the first P142 fix attempt and in a P155b comment.
