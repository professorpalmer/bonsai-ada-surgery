# Events, 2026-10-13 to 2026-10-14 (range p109-p132)

Notebook entries in this range that are not experiments: releases, PRs, issue threads, decisions, incidents and
lessons. Sources: `C:\bonsai\8gb\DECISIONS.md` (NOTEBOOK.md here) from the entry "2026-10-13 P114 (partial, speed
done) and P116 (plan)" to the end (entry "2026-10-14 06:43Z 4070: sparse 245k copy miss ..."), receipts/queue.log,
the receipts named below, and the GitHub threads (issue #21, issue #22, PR #40, PR #49, PR #56). Numbering continues
from `events-p090-p108.md` (E1-E22). Times with "Z" are UTC (GitHub, notebook headings); other times are rig local time
(CDT, UTC-5). The GitHub posts of both sessions use the same account; "4070" and "2060" name the session.

- [E23 Recap: the sparse VRAM allocations, 8d5b862fc and 3299a0b4b (MIN_HOST)](#e23-recap-the-sparse-vram-allocations-8d5b862fc-and-3299a0b4b-min_host)
- [E24 Releases: bundle-20261011 and bundle-20261013, and their 2060 checks](#e24-releases-bundle-20261011-and-bundle-20261013-and-their-2060-checks)
- [E25 PR #40 (patch 0054): the sm_75 review and the device-check change](#e25-pr-40-patch-0054-the-sm_75-review-and-the-device-check-change)
- [E26 Issue #21: the 4070's D18 and the re-asked runs](#e26-issue-21-the-4070s-d18-and-the-re-asked-runs)
- [E27 Cary: ship sparse first, q3_0 later](#e27-cary-ship-sparse-first-q3_0-later)
- [E28 Issue #21: the root cause of the P118 cost (eligibility vs prefetch)](#e28-issue-21-the-root-cause-of-the-p118-cost-eligibility-vs-prefetch)
- [E29 product-sparse 3ab0af3c2 and launcher PR #49](#e29-product-sparse-3ab0af3c2-and-launcher-pr-49)
- [E30 The page-bound reserve: options, and the 4070's default rule](#e30-the-page-bound-reserve-options-and-the-4070s-default-rule)
- [E31 int8 page bounds c8bbb1898 (514 B per host cell); launcher 8a47ffe](#e31-int8-page-bounds-c8bbb1898-514-b-per-host-cell-launcher-8a47ffe)
- [E32 2026-10-13 power cut](#e32-2026-10-13-power-cut)
- [E33 4070 D21: sparse on the product base](#e33-4070-d21-sparse-on-the-product-base)
- [E34 2026-10-13 system crash (bugcheck 0x3B, Windows servicing)](#e34-2026-10-13-system-crash-bugcheck-0x3b-windows-servicing)
- [E35 4070 D22 (int8 bounds) and patch 0055 = draft PR #56](#e35-4070-d22-int8-bounds-and-patch-0055--draft-pr-56)
- [E36 q3_0 port 4dbfe57d4: the 4070 gates and the Q06 request](#e36-q3_0-port-4dbfe57d4-the-4070-gates-and-the-q06-request)
- [E37 Lessons recorded in this range](#e37-lessons-recorded-in-this-range)
- Continued in [`events-p133-p155.md`](events-p133-p155.md) (E38-E56)

## E23 Recap: the sparse VRAM allocations, 8d5b862fc and 3299a0b4b (MIN_HOST)

| | |
| --- | --- |
| Date | 2026-10-13 16:02Z (11:02 rig time) and 16:32Z; full entry in `events-p090-p108.md` E21 |
| Allocation sizes (4070) | Only with GGML_CUDA_FA_SPARSE, at the first sparse op (the first decode step): page-bound tables, f32 max + min per page / head / dim, 2 KiB per host cell (227 MiB at 160k, 393 MiB at 245k), and a first fill of the whole host tail of K as f16 (219 / 385 MiB), kept by the pool's high-water mark. Up to ~780 MiB over the dense arm at 245k = the P107 over-commit |
| 8d5b862fc | Bounds in f16 (1 KiB per host cell: 114 / 196 MiB) + first fill in chunks of GGML_CUDA_FA_SPARSE_FILL_CELLS=16384 (32 MiB). Sparse fixed cost at 245k ~230 MiB. Proposed launcher term: host cells x 1 KiB x (64 / page) + 36 MiB |
| 3299a0b4b | 8d5b862fc + GGML_CUDA_FA_SPARSE_MIN_HOST=N (dense while the host tail < N cells; 0 = off) |
| 2060 results in this range | P111 (margin 475: 2.23x at 245k with op timing), P112 (MIN_HOST=32768: 160k 2.15x, 64k -20 %), P115 (245k 2.68x clean; the 64k cost always-on), P118 (the cost is in FLASH_ATTN_EXT), P121 (crossover 1.45x at 96k, 1.78x at 128k), P109b (the old build cannot be covered by margin: 3,328 cells) |
| Links | E21; P109, P109b, P111, P112, P115, P118, P121 |

## E24 Releases: bundle-20261011 and bundle-20261013, and their 2060 checks

| | |
| --- | --- |
| bundle-20261011 | Published 2026-10-13 16:58:34Z by the 4070 session (90ca41e40, 53 patches; new: patch 0053 tier-graphs). Zip 610,429,298 B, SHA-256 f8899cbf...da8bf8 (E22). 2060 check P113 (14:35-15:16): PASS; decode 53.9 / 47.9 / 38.0 / 27.9 / 16.9 at 4k-128k; posted on #22 (6154352801) with the line correction (62,464 vs P96's 57,600) |
| bundle-20261013 | PR #51 (release commit, README note and gate results) merged 2026-10-14 01:53:26Z; release published 01:56:00Z (20:56 rig time), "faster prefill on RTX 30 and 40 (patch 0054)". Zip 610,554,885 B, SHA-256 dda336ab1473707724078e42f81e720cbf7c286954004db85827c602b03e5a51. Engine (release notes): de873117e1 = PrismML adfffbe + 54 patches. 4070 gates (#21, 01:57Z): prefill +6.9 / +6.1 / +3.3 % at 4k / 32k / 128k, decode within 2 %, HumanEval 158/164 (release notes: 160/164 before; "two long-thinking answers changed with the float order"). The release notes quote P116b for RTX 20 cards |
| New reference | The 4070 on #21 (01:57Z): "For the sparse gates, the 'no loss vs' reference is now bundle-20261013". P124 / P128 gate headers changed before their runs |
| 2060 check of bundle-20261013 | P126 (first run cut by the power cut, E32; rerun 21:59-22:40): sha, tests, GDN skip line, 0 one-token, min free PASS; 64k-128k -5.0 / -6.8 / -3.6 % vs P113 = FAIL as written. P126b (first run cut by the crash, E34; rerun 00:10-01:04): bundle-20261013 vs bundle-20261011 alternated in one session, -1.0 / -0.2 / +1.5 % = PASS. Release verdict PASS. Posted on #40 (6162050637, 06:05Z) |
| Links | P113, P116, P116b, P126, P126b; E22, E25 |

## E25 PR #40 (patch 0054): the sm_75 review and the device-check change

| | |
| --- | --- |
| Date | Request on #21 2026-10-13 21:35Z (6155699422); P116 post on #40 22:09Z (6156235014); 4070 change and merge 22:46Z (6156817784; merged 22:46:10Z); P116b post 23:34Z (6157443338) |
| Request (4070) | PR #40 = patch 0054, chunked gated-delta-net prefill with BF16 MMA (port of ggml-org/llama.cpp#29353), branch product-0054 e63ce36d9. "On sm_75 the chunked path must not be taken: BF16 MMA needs Ampere GA10x / Ada." Gates: WARN skip line and no engaged line; 32k prefill and decode equal to product-0053; GATED_DELTA_NET op tests |
| Review (2060, from code reading and P116) | On sm_75 the line was "not taken", not "skipped": the branch is entered (n_mma >= 64, scalar gates), allocates g_act / b_act / s_mid, runs gdn_activate_raw_gates, and only then finds in ggml_cuda_gdn_mma_launch that the device has no BF16 MMA. No measurable cost (P116: within 0.2 %). Suggested a device check before the allocations |
| Change (4070) | 0054 = de873117e (force-pushed): the device is checked before any temporaries; cards without the BF16 MMA schedule log "chunked GDN prefill (MMA) skipped: device cc N ..." and keep the recurrent kernel; Ada and GA10x run the same code. 4070: GATED_DELTA_NET 55/55 ("the earlier '57' in D14 was a count of OK lines"); adfffbe + patches 0001-0054 -> tree 165e10e3, the same as the branch. Merged |
| Check | P116b on de873117e: 55/55, "skipped: device cc 750" once, 0 not taken / engaged, 32k within 0.7 % of bundle-20261011. Quoted in the bundle-20261013 release notes |
| Links | P116, P116b, P126; E24 |

## E26 Issue #21: the 4070's D18 and the re-asked runs

| | |
| --- | --- |
| Date | 2026-10-14 00:02Z (19:02 rig time on 10-13; 6157788666); 2060 reply 00:02Z (6157796219); notebook entry "2026-10-14 00:1x #21: the 4070's D18 PASS ..." |
| D18 (4070) | 8d5b862fc (3299a0b4b adds only MIN_HOST), 8 GB-like layout, line 32,768, 160k, B 8192 / P 64: FLASH_ATTN_EXT 3005/3005; sparse_edit with CHECK: track 0 / 0 / 0 stale ops (notrack control 0 / 192 / 192); copies / needles 10/10, 12/12 (before and after); peak VRAM 9,747 -> 9,356 MiB (-391 MiB; estimate for a 126,720-cell host tail ~344 MiB); mean decode 25.5 -> 27.6, read as run spread |
| Re-asked | "P110 on 3299a0b4b" (the 245k run with margin 475): it had run as P111 (PASS). "Then P111 (96k and 128k) for the MIN_HOST crossover": queued as P121 |
| 2060 reply | Links to P111, P112, P115, P118; suggested the routing fix first, then the crossover again on the fixed build |
| Links | P111, P112, P115, P118, P121 |

## E27 Cary: ship sparse first, q3_0 later

| | |
| --- | --- |
| Date | 2026-10-14 ~00:5xZ (notebook); proposal posted on #21 00:49Z (6158361458); 4070 agreed 00:53Z (6158411381) |
| Decision (Cary) | "ship sparse first, q3_0 later, unless the 4070 has critiques" |
| Reason (post) | Sparse is nearly ready on 8 GB; q3_0 needs a rebase (8gb-backup/kv-q3-0 is 46 files on 2cadbfb64 and will conflict with the sparse attention code). Users get 2.7x at 245k without waiting |
| Remaining sparse steps (post) | The P118 routing fix; the launcher term (host cells x 1 KiB x 64 / page + 36 MiB) in place of BONSAI_VRAM_MARGIN=475, with FA_SPARSE=8192,64,1024, FAST=1 and MIN_HOST from P121; release gates: the 4070's D18 set, and on the 2060 the release sweep 4k-128k (no loss beyond 3 %), 160k / 245k >= 1.8x dense, fresh 60k, 0 one-token, trace min free >= 60 MiB, a HumanEval on the bundle's own binaries |
| 4070 answer | "Agreed: sparse first, q3_0 after it." With the P118 root cause (E28) and the plan for product-sparse (E29) |
| Then q3_0 | Rebase onto the sparse bundle, then P108 / P114 / P117 again on the new build (E36: P129-P132) |
| Links | P114, P115, P117, P118, P121; E28, E29, E36 |

## E28 Issue #21: the root cause of the P118 cost (eligibility vs prefetch)

| | |
| --- | --- |
| Date | 2026-10-14 00:53Z (6158411381); 2060 reply 00:53Z (6158419137) |
| Cause (4070) | "It is not in the kernel. Graph setup (ggml-cuda.cu, tier prefetch) leaves out every attention op that ggml_cuda_fa_sparse_eligible() accepts. That function does not check MIN_HOST." Below the threshold the op gets no sparse mask (ggml_cuda_fa_sparse_mask checks MIN_HOST) and no prefetch; with STAGE_MIN_Q=9 a decode op then reads the whole host tail in place over PCIe. That is P118's 7.8 -> 22.8 ms and P115's -20.6 % |
| Fix | One eligibility check used by both places (9d9a968d9, in product-sparse 3ab0af3c2). Checked on 8 GB by P123: 0 sparse ops at 64k; the -20.6 % is gone (the -7.0 % left is the line) |
| Graphs | On a 0053 base the sparse env needs no GGML_CUDA_DISABLE_GRAPHS: a sparse op engages only when its K reaches the host tail, and 0053 turns graphs off for exactly those graphs. Every earlier sparse run set graphs off by hand because fa-sparse-proto sat on 2cadbfb64 (no 0053) |
| Mask | Decode and verify ops up to 31 queries get an f16 mask even with --kq-mask-packed (I32 only from 32 queries), so the packed mask can stay on |
| 2060 note | P121 (MIN_HOST=0) cannot be touched by the bug; it reruns on product-sparse anyway because 0053 moves the dense arm (P122) |
| Links | P115, P118, P121, P122, P123 |

## E29 product-sparse 3ab0af3c2 and launcher PR #49

| | |
| --- | --- |
| Date | 2026-10-14 01:00Z (6158505655); 2060 queue post 01:04Z (6158544711) |
| Engine | Fork product-sparse 3ab0af3c2 = product-0054 de873117e + the sparse ggml work up to 9d9a968d9 (the MIN_HOST eligibility fix), as one commit (patch 0055 candidate). The LLAMA_SLOT_KEEP_TOKENS server prototype is not in it. Built for sm_75 / 86 / 89 |
| Launcher | Draft PR #49 (branch launcher-sparse, c1908b7): with this engine on 8 GB it sets GGML_CUDA_FA_SPARSE=8192,64,1024, FAST=1, MIN_HOST=32768 (provisional, from P112), counts the page bounds in the VRAM line ((Ctx - N) x SparseCellBytes + 36 MiB), sets no DISABLE_GRAPHS and no mask change. BONSAI_SPARSE=0 turns it off |
| 2060 setup | Test copy start-server-sparsetest.ps1 = c1908b7 + the BONSAI_BIN line (local only). prism-tiergraphs branch product-sparse-2060 = 3ab0af3c2; built in tooling/build-tiergraphs inside P122 -> bin-psparse |
| Queue (2060) | P122 (build, op tests, crossover), P123 (64k routing check, x2), P124 (release-style sweep, 160k / 245k vs off), P125 (HumanEval), then P119 / P120. P120 rewritten to bin-psparse + launcher-sparse defaults (P120 record) |
| Links | P120, P122-P125; E28, E30 |

## E30 The page-bound reserve: options, and the 4070's default rule

| | |
| --- | --- |
| Date | P122 post 2026-10-14 02:13Z (6159358150); 4070 answer 02:19Z (6159428007); P123 post 04:04Z (6160632088); 4070 answer 04:09Z (6160684114) |
| Finding (P122) | The launcher counts "244 MiB of page bounds" for the 262k window: line 62,464 -> 48,640 (-13,824 cells); min free 195 vs 70 MiB at 128k. The reserve is paid at every depth: sparse 1.02x at 96k, 1.17x at 128k |
| Options (2060) | Reserve bounds only beyond MIN_HOST, or tables that grow with depth; page 128 (0.5 KiB per cell, ~122 MiB); bounds in pinned host memory |
| 4070 answer | The reserve is for the full window because the line is fixed at load. Beyond MIN_HOST only: 32,768 x 1 KiB = 32 MiB of 244, ~2k cells back. Pinned host bounds: 213k host cells x 64 B per cell per layer x 16 layers = ~218 MB per token over PCIe 3 (~12 GB/s) = ~18 ms per token, +45 % at 25 tok/s. Page 128: ~7k cells back but no quality data (P 256 lost exact copies). Pick: int8 bounds at P 64, one f16 scale per page and head, rounded outward (max up, min down), so the page score stays an upper bound: ~124 MiB at 262k, ~7k cells back (E31) |
| Default rule (4070) | "64k within ~5 % of BONSAI_SPARSE=0: sparse on by default on 8 GB at 262k; 64k worse than that: I wait for the 8-bit bounds, which halve the line cost." The summary line prints the line without and with sparse and the depth trade, so a user who stays below ~100k can choose BONSAI_SPARSE=0 |
| Outcome | P123 (f16 bounds): 64k -7.0 % -> wait for int8 (P127). On trimming the reserve (~200 MiB more free at 64k): "please keep it for now"; the tables fill as the host tail grows; decide from the 245k trace minimum, sparse vs dense (P124 / P128) |
| Links | P122, P123, P124, P127, P128; E31 |

## E31 int8 page bounds c8bbb1898 (514 B per host cell); launcher 8a47ffe

| | |
| --- | --- |
| Date | 2026-10-14 02:22Z (#21 6159472110; #49 6159471548); 2060 queue post 02:25Z (6159506733); layout post on #49 05:57Z (6161950610) |
| Engine | product-sparse c8bbb1898 = one commit on 3ab0af3c2: int8 bounds, one f16 scale per page and head, rounded outward. The f16-mask warning now prints only for decode-sized ops (a packed prefill op triggered it before) |
| Layout (#49) | "each page and KV head stores D int8 max + D int8 min + one f16 scale = 2 x 256 + 2 = 514 B. For 16 layers x 4 heads per page of 64 cells: 16 x 4 x 514 / 64 = 514 B per host cell." One scale per page and head, so not 516 |
| Launcher | 8a47ffe (PR #49): detects "bounds int8" in ggml-cuda.dll and counts `16 * 4 * (2 * 256 + 2) / P`, else `16 * 4 * 2 * 256 * 2 / P`; the summary prints "VRAM line <dense> -> <sparse>" and the depth trade (review note 3) |
| 2060 plans | P127 (build c8bbb1898 + P123 again, 5 % rule, 2 % reported), P128 (P124 again). P120 rewritten to bin-psparse8 + 8a47ffe. Launcher test copy start-server-sparsetest2.ps1 |
| Links | P120, P127, P128; E30, E35 |

## E32 2026-10-13 power cut

| | |
| --- | --- |
| Date | 2026-10-13. Notebook: "~21:35 power cut; reboot 21:40; resumed 21:59". Queue NOTE 21:59:24: "power cut ~21:3x (reboot 21:40)". The 4070 (#21, 03:50Z): "A power cut at about 21:40 stopped the first run" (both rigs) |
| Time from the receipts | The P126 sweep trace (receipts/p126-interrupted-power/sweep.mem.txt) ends at 21:27:23; the server log's last line is at ~21:27:14 (128k prompt at "progress = 0.94"). The OS started again at 21:40:26 (System event log: Kernel-General 12; Kernel-Power 41 at 21:40:28). So the power was lost at ~21:27, and the reboot was at 21:40 |
| Bugcheck | None: Kernel-Power 41 and 6008, no bugcheck, no dump |
| State after the reboot | GPU 42 C, fan 40 % (slot 5 not applied), memory stock, PCIe 3 x16; BonsaiQueue task Ready, runner not running |
| Recovery | P126 receipts moved to receipts/p126-interrupted-power, the job back to pending and rerun from the start (zip and x/ on disk). Slot 3 -> 5 re-applied (fan 100 %). resume.ps1: the runner took the stale lock; P126 running again 21:59:26. P121 / P122 were complete before the cut |
| Links | P126; E34 |

## E33 4070 D21: sparse on the product base

| | |
| --- | --- |
| Date | 2026-10-14 03:50Z (6160464253) |
| Setup | product-sparse 3ab0af3c2 (bundle-20261013 engine + sparse), CUDA graphs on, packed mask on, line 32,768, 160k, B 8192 / P 64 / R 1024, product memory clock. A full rerun after the power cut |
| Result | Mean decode at 160k dense 13.8, sparse 27.5 (2.0x); copies / needles 10/10, 12/12 both; cold prefill 571 / 605; op tests FA 3005/3005, GDN 55/55; edit test 0 stale ops with tracking (control 272); min free 2,871 MiB; CUDA graphs stay on (1,820 graph lines in the sparse server log); one warmup "needs an f16 mask" line (a prefill op) |
| Note | "The kernel session is offline after the cut, so the 4070 release session runs its queue for now" |
| Links | E29, E35 |

## E34 2026-10-13 system crash (bugcheck 0x3B, Windows servicing)

| | |
| --- | --- |
| Date | 2026-10-13. Notebook heading: "23:40:37 system crash (bugcheck 0x3B), reboot 23:56; resumed 00:1x". The #21 (05:59Z) and #40 (06:05Z) posts say "23:40" |
| Time from the receipts | 23:40:37 is the time in event 6008 ("The previous system shutdown at 11:40:37 PM ... was unexpected"). The P126b first run was still running after it: its fourth server (1013 r2) started at 23:43:58, wrote its 96k result at 23:52:21 (receipts/p126b-interrupted-crash/b1013_r2.txt), and its server log runs to ~23:55:54. The OS started again at 23:56:16; the dump was written at 23:56:24. So the crash was at ~23:56. Event 6008 times are not crash times on this machine: after the power cut, 6008 said "8:48:43 PM", while P122 ran until 21:12 |
| Event log | Kernel-Power 41; WER 1001 "rebooted from a bugcheck 0x0000003b (0xc0000005, 0xfffff800ee14fb24, ...)"; 6008 |
| Dump analysis (by hand) | C:\Windows\Minidump\101326-9656-01.dmp (4,310,942 B, PAGEDU64 triage), parsed by hand (no debugger installed): faulting IP = ntoskrnl.exe+0x34fb24; process (EPROCESS) = TiWorker.exe (Windows Modules Installer, Windows Update servicing); stack modules ntoskrnl only (+ two unnamed); no nvlddmkm / dxgkrnl / llama-server frame |
| Servicing activity (System / Setup logs, read for this record) | Windows Update downloads from 23:46:06; servicing package changes from 23:47:23; security update install started 23:52:01; WinREAgent "Starting Windows Recovery Environment servicing" 23:52:23; an update reported installed at 23:58:43 after the reboot. No update or servicing event between 21:51:26 and 23:46:06 |
| Reading | A Windows servicing crash, not the GPU workload (stock clocks, slot 5) |
| Recovery | P126b partial receipts -> receipts/p126b-interrupted-crash; job back to pending; rerun 00:10:04-01:04:45. Slot 3 -> 5 re-applied. The queue log has no NOTE line for this crash (only "RESUMED" and the stale-lock takeover at 00:10) |
| Suggestion to Cary | Let Windows finish, or pause updates during long runs (his call: a system setting) |
| Links | P126b; E32; TOOLBOX section 10 |

## E35 4070 D22 (int8 bounds) and patch 0055 = draft PR #56

| | |
| --- | --- |
| Date | D22 2026-10-14 05:56Z (6161934290); 0055 05:57Z (6161950848); 2060 reply 05:59Z (6161977645) |
| D22 (4070) | c8bbb1898 (int8) vs 3ab0af3c2 (f16), graphs on, packed mask on, line 32,768, B 8192 / P 64 / R 1024: mean decode 160k 27.3 vs 27.5, 245k 24.5 vs 23.0; copies / needles 160k 10/10, 12/12 both; 245k 9/10, 12/12 both (the same miss in both: _pydecimal.py _convert_other at 44 % of the context; a dense control at 245k queued there); peak VRAM at 245k 9,164 vs 9,309 MiB; edit test 0 stale ops; the warmup f16-mask line gone |
| Patch 0055 | Draft PR #56: fork product-0055 578262610 = bundle-20261013 + sparse with int8 bounds, the same tree as c8bbb1898. The launcher half is #49 (514 B per host cell). "Both PRs stay draft until your P124 / P127 pass on c8bbb1898. P127 is the deciding run" |
| 2060 reply | P124 (3ab0af3c2) and P128 (c8bbb1898) log the 245k trace minimum per arm; P127 prints the "VRAM line A -> B" line. The interrupted P126b already showed bundle-20261013 = bundle-20261011 in one session |
| 245k copy miss (06:43Z, 6162565090) | 4070 dense control at 245k (c8bbb1898 root, graphs on, packed mask on, line 32,768): copies 10/10, needles 12/12, decode 8.8 tok/s. Sparse B 8192 / P 64 / R 1024 (int8 and f16 bounds): 9/10, 12/12, the same item (_pydecimal.py _convert_other, 18 lines, at 44 %). "So at 245k the sparse selection loses that copy; the model alone does not." At 160k sparse is 10/10 (D21, D22). B 8192 is about 4 % of a 212k-cell host tail. B 16384 and B 12288 running on the 4070. "#56 and #49 wait for this answer" |
| 2060 data (06:48Z, 6162628183; notebook 06:43Z entry) | P105 (d6c6e9f01, f16 bounds, B 8192 / P 64, 2026-10-11) at 245k: dense 10/10, sparse 9/10, the miss _strptime.py _calc_julian_from_U_or_W (position 0.554); needles 12/12 both. The rig's item list is built locally, so _convert_other is not in it. Queued P133 (queue 69if2, after P127): 245k copies and needles on c8bbb1898 with launcher 8a47ffe, fresh servers, arms dense / sparse B 8192 / sparse B 16384, every missed item printed. P125 moved to 69il (after the q3_0 set). Queue: P124 (running) -> P127 -> P133 -> P128 -> P129-P132 -> P125 -> P119 -> P120 |
| Latest at the time of writing (06:52Z, 6162684377) | The kernel session's lead is ranking, not budget: the page score is the maximum over all 24 Q heads, so a quiet retrieval head can lose its pages. product-sparse 8d6e0d3f4 adds GGML_CUDA_FA_SPARSE_NORM=1 (rank each page by each head's bound relative to that head's best page); asked for a fourth P133 arm (B 8192 + NORM=1). Not in the notebook yet |
| Links | P105, P124, P126b, P127, P128; E31 |

## E36 q3_0 port 4dbfe57d4: the 4070 gates and the Q06 request

| | |
| --- | --- |
| Date | PR #50 (docs/research/q3port-20261013, gates before runs) merged 2026-10-14 01:14:15Z; PR #58 (q3port Q03-Q05 pass) merged 06:11:35Z; request on #21 06:11Z (6162132292); 2060 queue post 06:14Z (6162163752) |
| Builds | PR #50 plan: q3-on-sparse bae6dccfe = product-sparse 3ab0af3c2 + q3_0; fallback q3-on-0054 80b4eab7a (local). Final: q3-on-sparse 4dbfe57d4 = c8bbb1898 (the patch 0055 tree) + q3_0, one commit, a clean pick of 6a4851286 |
| 4070 gates | Q03 op tests with q3_0 cases: FLASH_ATTN_EXT 3115/3115 (110 q3_0 cases), SET_ROWS 177/177, CPY 259/259, GET_ROWS 123/123. Q04 PPL, wikitext-2 at -c 2048, 32 chunks: q8_0 8.0733, q4_0 8.0900, q3_0 8.1366 (+0.58 % vs q4_0; gate 1 %). Q05 sparse (int8 bounds) + q3_0 K/V at 160k, line 32,768, graphs on, packed mask on: copies 10/10, needles 12/12 |
| Q06 request | On the 2060, after P124 / P127 / P128 (sparse first): build 4dbfe57d4 for 75-real; P108 (PPL q4_0 vs q3_0), P114 (decode at 128k / 192k and the line), P117 (HumanEval with q3_0); then sparse on with q3_0 and q4_0 at 160k / 245k. "The launcher has no q3_0 entry in its cell-size table yet (it falls back to the q8_0 size, so the line is too low, not unsafe)" |
| 2060 plans | prism-q3kv -> branch q3-on-sparse-2060 = 4dbfe57d4, own build dir build-q3kv (P127's build in prism-tiergraphs untouched). Launcher test copy start-server-sparsetest2q3.ps1 = sparsetest2 + 'q3_0' { 14336 }. P129 build + op tests + PPL; P130 the P114 set (sparse off); P131 HumanEval q3_0; P132 sparse on, q4_0 vs q3_0, 160k -> 245k. P119 / P120 renamed 69m / 69n to run after them |
| Links | P108, P114, P117, P129-P132; E27 |

## E37 Lessons recorded in this range

- P126b (notebook): "release-vs-release only inside one session (alternated); a release check gates on the
  same-session A/B." Session-to-session moves on this card were ~5 % at 64k (P126 vs P113, P126b first run vs rerun).
- P111 / P122 / P123 / the 4070 (04:09Z): trace free VRAM every 10 s in every arm. A table that fills with depth
  leaves free VRAM at 64k that is not spare at 245k; decide any trim from the deepest trace minimum.
- P107 / P111 (kept): read wrapped nvidia-smi values (free near 4,194,304 MiB) as an over-commit; in awk add 0 to a
  field before a numeric compare.
- P122 / P123: the launcher reserve vs line trade. The page-bound reserve must cover the full window (the line is fixed
  at load), so it costs line cells at every depth: f16 bounds 244-245 MiB = 13,824 cells = -7.0 % at 64k (P123) and
  the whole 96k gain (P122). Shrink the bytes per cell (int8) before trading quality.
- P109b: compute the line a margin leaves before the run (1,025 MiB -> 3,328 cells at 262k).
- P121 / P122 / P114 (found by this record writer): a step named "extend" in a script can be a full prefill; check the
  evaluated token count.
- E32 / E34 (found by this record writer): Windows event 6008 times are not crash times; time an outage from the last
  receipt, trace sample or server log line.
- E34: long unattended runs can be cut by Windows Update servicing (here a 0x3B bugcheck in ntoskrnl from TiWorker.exe
  at ~23:56); pause updates during long runs, or let servicing finish first (Cary's call).
- E32 / E34: after any reboot, re-apply Afterburner slot 3 then 5 (it came up with fan 40 %), and keep interrupted
  receipts in a separate folder with a NOTE line in the queue log.
