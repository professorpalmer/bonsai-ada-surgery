# Events, 2026-10-16 to 2026-10-17 (range p162-p168)

Notebook entries in this range that are not experiments: releases, PRs, issue threads, decisions, incidents and
lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-16 22:55 CDT (clock time; some
evening headings above run up to ~75 min ahead) CORRECTIONS from the records review" to the entry "2026-10-17 05:04 CDT
VRAM line 86,784 vs 80,640: explained (no fix)" (the next entry, "05:09 CDT P169 queued: T4-A fast read on the 2060 ...",
is the next range), receipts/queue.log, the receipts named below, the threads of issues #138 and #105, PRs #159 and
#164, and the PR list of this repo (titles and times). Numbering continues from `events-p156-p161.md` (E57-E66). Times
with "Z" are UTC (GitHub); "CDT" and other times are rig local time (UTC-5). The GitHub posts of all sessions use the
same account; "4070", "2060", "kernel session" and "release session" name the session.

- [E67 The records-review corrections and the P156-P161 records (PR #163)](#e67-the-records-review-corrections-and-the-p156-p161-records-pr-163)
- [E68 Release-0062 and bundle-20261017](#e68-release-0062-and-bundle-20261017)
- [E69 PR #159 read ahead: review, fixes, merge](#e69-pr-159-read-ahead-review-fixes-merge)
- [E70 The serve folder for Cary (serve-1017)](#e70-the-serve-folder-for-cary-serve-1017)
- [E71 T4-A fast read: plan, gates, first 4070 numbers](#e71-t4-a-fast-read-plan-gates-first-4070-numbers)
- [E72 The spill guard (PR #164): v2 to v5 and the forward-slash fault](#e72-the-spill-guard-pr-164-v2-to-v5-and-the-forward-slash-fault)
- [E73 The VRAM line 86,784 vs 80,640](#e73-the-vram-line-86784-vs-80640)
- [E74 Corrections in this range](#e74-corrections-in-this-range)
- [E75 Lessons recorded in this range](#e75-lessons-recorded-in-this-range)

## E67 The records-review corrections and the P156-P161 records (PR #163)

| | |
| --- | --- |
| Date | Notebook entry "22:55 CDT (clock time; some evening headings above run up to ~75 min ahead) CORRECTIONS from the records review". PR #163 opened 03:41:02Z, merged 03:41:11Z |
| What | The records agent for P156-P161 found five errors; the notebook took them: "1. P160 part A did NOT run on the shipped bins: serve() ignored its 2nd argument; it ran on bin-slotdraft + pool off. No receipt for shipped bins + pool off. 2. P160 part B layer restores had no draft sidecar (B1 bug). 3. P157b: BONSAI_SPEC=0 also turned the shared pool off (confound); the cause is the shared pool (P158c/P158b/P158d). 4. P156d code 20/20 both arms (summary key collision showed 19/19). 5. P156 queue names: try 2 = 69jeb5, Q2 = 69jea92/69jea94." |
| Posts | "The #138 posts for P160 and P157b now start with these corrections" (the P160 post 6228476436 was edited) |
| Clock | The heading says "(clock time ...)" (the E65 lesson). Found by this record writer: the headings "23:05 CDT" to "23:28 CDT" still run 3-20 min ahead of the GitHub times (PR #159 review 03:45:10Z = 22:45 CDT, heading "23:05"; merge 04:25:49Z = 23:25, heading "23:28"). The 2026-10-17 headings agree with the GitHub times within 8 min |
| Links | PR #163; `events-p156-p161.md` E65; P157; P160 |

## E68 Release-0062 and bundle-20261017

| | |
| --- | --- |
| Date | PR #160 "release: patches 0062-0066 (saved conversations on 8 GB), bundle-20261017" merged 03:26:15Z; published 03:32:59Z (notebook "22:40 CDT"); card PR #161 03:33:25Z; research PR #162 "release-0062 S5-S7" 03:34:57Z; the S7 ask on #105 03:34:39Z; P163 posted on #105 04:11:08Z |
| What | Saved conversations on every card: the draft sidecar (0062 / 0063), the VMM pool fix (0064 retries / RESERVE_MIB, 0065 POOL_LOG, 0066 16 MiB pieces) and the layer cache (#157). "a 199k conversation answers ~6 s after a server restart on the 2060 SUPER; `BONSAI_SHARED_POOL=0` is no longer needed" (#105) |
| Zip | 616,666,781 B, sha256 723c12e6...c253, engine 96f6e49cdc, launcher / layer 2db3fa21 |
| 2060 check | P163 PASS: sha, op tests, cold 128k 529.28 s, 4k 53.4 / 64k 41.2, S1 restore 227.3 / 227.7 tok/s, 0 CUDA errors. The S7 plan's 131k restore did not run (E74) |
| Links | P163; P158d; `../release-0062/`; issue #105 |

## E69 PR #159 read ahead: review, fixes, merge

| | |
| --- | --- |
| Date | PR #159 opened 03:20:47Z; P162 post 03:42:43Z; review 03:45:10Z; fixes 410e497 03:50:11Z; re-review 03:58:39Z; fixes 8e9b562 04:02:00Z; verified 04:06:10Z; rebased as one commit 98203aa 04:09:16Z; merged 04:25:49Z (23:25 CDT) |
| P162 (2060) | Read ahead PASS on bin-0060p with the layer at 5e90852: 130,452 tokens saved, restart + ask 6.25 s vs cold 560.7 s, same answer, 0 CUDA errors |
| Review (release session) | Notebook "23:05 CDT": "2 blocking (interpreter stream no early bytes; cache-off prefill_only generates) + route / status / churn: fixed in 410e497, tests 14/14 (fake template renders tool names)". Re-review, notebook "23:15 CDT": "held after a restore-only read-ahead (blocking), 502 on server-gone (interpreter route), keepalive 0 no comments: fixed, tests 15/15" |
| After the merge | Notebook "23:28 CDT": "serve-1017/layer updated from main (bonsai_layer.py, slot_cache.py); SERVE_FOR_MAC.md updated". P164 and P165 ran this layer (main bad2d9a) |
| Links | P162; P164; P165; PR #159; issue #138 |

## E70 The serve folder for Cary (serve-1017)

| | |
| --- | --- |
| Date | Notebook entries "23:20 CDT Serve folder C:\bonsai\serve-1017 ..." and "23:28 CDT PR #159 (read ahead) merged ..." |
| What | "Serve folder C:\bonsai\serve-1017 (bundle-20261017 zip + models junction + slots) and SERVE_FOR_MAC.md written for Cary (pause queue, BONSAI_SLOT_SAVE_PATH, LAN <lan-ip>:8080, key file path, firewall rule + layer runtime fetch are his one-time steps)." The LAN address is redacted here |
| Tests on it | P164 (a 30-turn soak, ~131k to ~250k, 9 restarts: PASS) and P165 (the demo clip: restart + Q1 first token 5.3 s at 199k: PASS) ran this folder's launcher, bin and layer |
| Links | P164; P165; E69 |

## E71 T4-A fast read: plan, gates, first 4070 numbers

| | |
| --- | --- |
| Date | T4 plan from the 2060 on #138 03:18:01Z (the previous range); kernel session T4-A design and gates 06:54:15Z; the 2060's note 06:55:28Z; release session gates 08:37:47Z; 4070 round 1 09:28:58Z; P169 queued on the 2060 10:09:03Z (outside this range) |
| Design (kernel session) | `LLAMA_FAST_READ="keep=M[,min=N,sinks=S,window=W,layers=K,probe=L,rows=R,block=B]"`: a scoring pass over the first K blocks, per-token attention scores from the RoPE'd Q of the last R rows at a full-attention probe block; keep the first S tokens, the last W tokens and the best B-token blocks up to M; read only the kept tokens with the full model. First setting `keep=12288,min=32768,sinks=256,window=2048,layers=8,probe=7,rows=32,block=32` |
| Gates (kernel session) | F0 mode off byte-identical; F1 items n24 / n28 / copies at 64k / 128k / 245k; F2 cold TTFT. "worth a 2060 run and a launcher switch only if at 245k it is >= 3x faster (F2) AND loses <= 1 item per set (F1)" |
| Gates (release session) | T4-0 mode off = the product hashes ("T4-0 must pass, or T4 does not ship at all"); T4-1 cold TTFT at 245k vs the dense 467.8 s (4070); T4-2 needle n24 at 245k vs dense 24/24; "No pass / fail for T4 itself. It is an opt-in lossy mode" |
| Round 1 (4070) | T4-0 PASS; 245k 76.5 s per question vs dense 467.8 s (6.1x); n24 7/24 at `keep=16384`. "early-layer attention of this model is a weak selector. T4 stays an experiment until the retrieval numbers are close to dense" |
| Links | issue #138; P169 (next range) |

## E72 The spill guard (PR #164): v2 to v5 and the forward-slash fault

| | |
| --- | --- |
| Date | PR #164 opened 07:28:43Z; G4 recipe 07:28:34Z; P166 07:54:14Z; v3 07:55:53Z; P166b 07:56:43Z; v4 08:01:25Z; correction 08:13:44Z; P167b 08:35:29Z; G4 on PR #164 08:39:51Z; v5 08:50:36Z; P168 09:58:47Z |
| Why (release session) | "When another program takes VRAM after the server starts, the server does not fail. It becomes about 10x slower, with no message" (4070, 8 GB preset: a 4 GB ballast took a cold 64k read from 757 to 78.9 tok/s) |
| v2 5edcfe7 (P166, P166b) | A `spill` line when the server's shared usage grows > 256 MiB, or other programs hold > 512 MiB more than at the first /health AND < 512 MiB is free. The 2060 has ~282-305 MiB free with the server up, so a (free - 100) hog is ~180 MiB |
| v3 c345b33 (P167) | Rule (2): others >= 128 MiB more AND free < min(512 MiB, 0.6 x the free VRAM at the first /health) |
| The fault | Notebook "03:15 CDT CORRECTION: P166 G4b / P166b / P167 ballast arms invalid: forward-slash BONSAI_BIN made the guard's StartsWith($BinDir) miss the server process, so the guard never ran." #138: "So the "0 lines" in G4a was trivially 0 too." Product note: "users can set `BONSAI_BIN` with forward slashes too ..., and then the guard is silently off. Suggest normalizing both sides" |
| v4 02523b9 (P167b) | Rule (2) counts the other programs' Total Committed (a paged-out ballast has small Dedicated Usage). P167b, Windows-form path: 206 MiB hog -> "other programs took 379 MiB ... (133 MiB free)" before the read (16k read 70.1 tok/s); 1,500 MiB -> "1,673 MiB ... (119 MiB free)", then the read crashed; cold 128k 0 lines, 529.21 s |
| v5 7e4ac46 (P168) | After the PR #164 review: an invalid counter sample no longer stops the guard; rule (2) needs two samples in a row; the guard attaches only to its own server. P168: 1 h with the display and a playing browser, 0 lines; an 18 MiB end hog -> the line |
| What stands from the void runs | The card's behavior: a ~180-200 MiB hog after the start halves the 16k read; a 1,500 MiB hog makes the next big batch fail with CUDA out of memory |
| Links | P166; P167; P168; PR #164; issue #138 |

## E73 The VRAM line 86,784 vs 80,640

| | |
| --- | --- |
| Date | Noted in the P168 post (09:58:47Z); the release session's question 10:01:29Z; the 2060's table 10:04:10Z (comment 6232608181; notebook "05:04 CDT"); the margin note 10:09:03Z |
| Question | The release session: "`start-server.ps1` is identical between the bundle-20261017 release (2db3fa2) and main (bad2d9a). The branch adds only the guard block, which sits after the VRAM-line sizing ... So the guard cannot change the line." It proposed the display / headless detection as the cause |
| Answer (2060) | "not the guard, not the display mode. The line follows free VRAM at start." Other programs at start: 423 MiB to 02:50 (line 80,640), 332-339 MiB from 02:57 (86,784 / 87,296). "87,296 - 80,640 = 6,656 cells for 91 MiB, which agrees with the launcher's "about 80k cells per GiB"." The fillers moved by the same step (61,440 -> 66,304 / 67,072). The margin is 225 MiB in every log (400 MiB for the 131k long filler). "I do not know which process freed the ~90 MiB at 02:50-03:00" |
| Margin | "in the launcher, 1,300 / 1,000 is the all-VRAM path (`start-server.ps1` line 278). The tiered path with MTP sets 225 (line 285). That is the 225 in all the 2060 logs" |
| Decision | "Nothing to fix from this ...: the line did what it is meant to do." |
| Links | P168; issue #138 |

## E74 Corrections in this range

- P166 G4b, P166b and P167 (all arms): void as guard tests. BONSAI_BIN had forward slashes and the guard's
  `StartsWith($BinDir)` never matched the server's path (notebook 03:15 CDT; #138 08:13:44Z). The G4a "0 lines" of P166
  and P167 is void too (#138; the notebook names only the ballast arms). P167b is the valid run.
- P167b first start (03:11:41-03:13:14, queue log FAILED): the first text (one 1,500 MiB arm, forward-slash path) ran
  while a new file with the same name was written at 03:13:03; the runner then ran the new text. The first copy's
  big.txt was overwritten. Found by this record writer (queue/failed/, the 031152 server log).
- P163: the release-0062 S7 line asks for restores at 64k and 131k, >= 3 restores; the #105 ask says 64k x3 + 131k x1
  + one layer-cache restart turn. P163 ran 64k x2. Found by this record writer.
- P164: the restart gate "(+ any save)" has two readings; the script does not compute it. With the layer's save step
  (re-read + save) left out, all restart turns pass; with the save call only, all are over. The #138 post's "Answers of
  the repeated questions stayed the same at every depth" has one exception (the "above 5000" question at turn 5). The
  notebook's "restore 2.4-3.4 s" leaves out turns 4 and 7 (2.05, 2.21 s). Found by this record writer.
- P167 / P167b big arms: the "CUDA out of memory" text is only in P166b's server log; P167 and P167b have only
  "ggml-cuda.cu:110: CUDA error". Found by this record writer.
- P168: the 64k reads are 2.2-2.3 % faster than the reference (over a two-sided 2 % band); between reads
  utilization.gpu is 0 % in every sample, so the browser's load is not measured; the post's "~148 MiB at the first
  /health" does not match the trace (300 MiB after the load). Found by this record writer.
- gpu_counters.ps1: `-split '\'` is an invalid regex; the counter read failed in both P167b arms (notebook 03:40 CDT).
- Notebook order: the entry "22:45 CDT P162 result" comes after the entry "22:55 CDT (clock time ...)". The notebook
  copy here keeps the rig's order.
- NOTEBOOK.md copy: the LAN address in the entry "23:20 CDT Serve folder ..." is replaced with `<lan-ip>`. The rest of
  the appended text is the rig notebook's text.

## E75 Lessons recorded in this range

- P166 / P167 / E72: pass a Windows path in its Windows form (`cygpath -w`) to any tool that compares paths; print the
  value as passed in the receipt; a check that finds nothing must also prove that it ran.
- P167b: when a running job is invalid, stop it before a new file with the same queue name is written.
- P167b: in PowerShell `-split` is a regex split; a lone backslash pattern fails at run time.
- P164: write the gate's arithmetic into the script, so a gate has one reading.
- P168 / E73: on WDDM the VRAM line follows free VRAM at start (~80k cells per GiB); compare lines only with the
  "other programs" figure of the same log.
- P168: nvidia-smi utilization.gpu does not show video decode; a display-load soak needs its own load counter.
- P163: check the queue script against the release plan's check list before the run.
