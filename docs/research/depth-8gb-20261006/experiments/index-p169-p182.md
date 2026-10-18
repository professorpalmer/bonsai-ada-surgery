# Index, P169 to P182

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records PR #165 and its
corrections, the spill guard merge and bundle-20261017b with its R4, the cold-read cost model, the T4 rounds on the
4070 and the paraphrase gate, Cary's ask and the cold-read research, the T5 fork branch and its bins, the rig drift
between two numeric states, the pool reserve PR #171 and its open G2 ask, the filler time 13:10-13:47 and the filler
preemption, the T5 proposal) are in `events-p169-p182.md`, E76-E87. The previous range is `index-p162-p168.md`.

State at the time of writing: 2026-10-17 17:20 CDT by the rig clock (22:20Z). The last notebook entries in this
range are "16:02 CDT Fillers now yield to queued jobs (preempt_lib.sh)" and "16:53 CDT P182: window 32k / sink 1k / tail
1k = n24 24/24 (814.3 s), code 19/24 (801.1 s), prose (P178) 9/24 (807.8 s)". P183 (queue 69jebn, "dense prose again +
window-32k prose again (noise floor), 128k cold read + n24 at 128k with window 32k") is running from 16:53:47 and is
outside this range. PR #171 (the 8 GB pool reserve) is open; the T5 proposal (#138 21:54:09Z) is not decided.
Next range: [`index-p183-p188.md`](index-p183-p188.md) ([P183](P183.md)).

P174 stopped at T5-0 because the product zip's own answer bytes had moved since P169 (a rig drift between two numeric
states, cause open, E82), not because of T5. P174b repeats P174 with in-block identity gates. P178 R-3 is void (a bug in
the dense-layer mask path, fixed in d1cc7a4bd, P180).

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P169](P169.md) | 2026-10-17 05:09-06:51 | T4-A fast read on the 2060 (sm_75), `keep=16384,bmax=1`, n24 at 245k | T4-0 PASS; reported | Mode off = zip at 4k / 32k; 18,688 of 244,237 tokens read, scoring pass 180.8 s, 237.6-239.6 s per question (6.2x); n24 5/24 (dense 23/24), 1 wrong code |
| [P170](P170.md) | 2026-10-17 06:51-08:01 | Text-match pre-filter (BM25, keep 16,384) vs the full read, code and prose sets (~240k) | Reported | Code lex 13/24 (named 12/12, described 1/12) vs dense 20/24; prose lex 4/24 vs dense 11/24; dense cold 1,418.4 / 1,431.4 s |
| [P171](P171.md) | 2026-10-17 08:06-10:26 | Small-model scorer (Qwen2.5-1.5B P(Yes) per chunk) as the selector | Reported (1 false positive) | Scoring 73-77 s per question; code small 11/24, mix 13/24; prose small 13/24 as graded (12 by meaning), mix 12/24; fact kept prose 16 / 17 |
| [P172](P172.md) | 2026-10-17 08:01-08:06 | R4: post-zip check of bundle-20261017b, the zip's own launcher, defaults | PASS | sha match, 16/16 bin = 1017; cold 64k 308.6 tok/s (-0.2 %), 0 spill lines; 58 MiB ballast -> the line after 28 s; 0 CUDA errors; line 87,808 |
| [P173](P173.md) | 2026-10-17 10:26-10:27 | PTQ1_0 prefill matmul alone on sm_75 (test-backend-ops perf) | Reported | ptq1_0 MMQ 28.3 TFLOPS, cuBLAS fallback 31.8, f16 39.4, q8_0 28.0 at 4096 x 512 x 14336 |
| [P174](P174.md) | 2026-10-17 10:27-10:30 | T5 prefill window screen (mask emulation, c675d5c78) | STOPPED at T5-0 | bin-t5 env unset 55d8056e05da9685 / 4d487e489a89d005 vs P169's d72631aa / d77df25f: the zip moved, not T5 |
| [P174a](P174.md#p174a-which-factor) | 2026-10-17 10:31-10:32 | T5-0 diagnosis: zip + SPARSE=0 vs bin-t5 without SPARSE at 4k | Diagnosis | Both 55d8056e05da9685: not T5, not BONSAI_SPARSE; a rig drift (E82) |
| [P174b](P174.md#p174b-t5-0-and-c0-in-block) | 2026-10-17 10:34-12:07 | T5 screen with in-block T5-0: C0, C1, n24 245k, the P170 sets (window 16k / sink 1k / tail 1k) | T5-0 PASS; screen FAIL on prose | C0 engaged; C1 2/8 (only in-window facts); n24 23/24 (= dense); code 20/24 (= dense); prose 5/24 (dense 11); mask only 1,452.2 s |
| [P175](P175.md) | 2026-10-17 12:07-12:42 | T5 speed v0: the exact chunk skip (d048068ca) | S-0 PASS; S-2 crashed | 245k 1,452.2 -> 991.0 s (1.47x) at 32k chunks, n24 22/24; 8k chunks: CUDA error; 128k 484.1 s (1.10x) |
| [P176](P176.md) | 2026-10-17 12:42-13:10 | Is the chunk skip bitwise exact? 128k, skip off / on / off | EXACT | f3123196105baddf x3; prompt eval 532.5 / 483.1 / 532.8 s (server logs) |
| [P177](P177.md) | 2026-10-17 13:46-13:52 | The 8k-chunk crash: zip 8k / skip off / skip on at 32k | Diagnosis | Only skip on crashes (at ~18-20k tokens): the scan's host sync under CUDA graph capture (likely) |
| [P178](P178.md) | 2026-10-17 13:52-14:55 | T5 run-based skip (80998aa79): 245k, 128k, prose dense=4, prose window 32k | R-0 PASS; R-3 VOID | 245k 713.1 s (2.04x), n24 21/24; 128k 371.3 s (1.43x); prose w32 9/24 (807.8 s); dense=4 all "////" (bug) |
| [P179](P179.md) | 2026-10-17 14:55-15:01 | The capture guard (0ad1aa527): 8k chunks + window at 32k and 64k | PASS | 0 CUDA errors at both depths |
| [P180](P180.md) | 2026-10-17 15:01-15:04 | The dense-layer bug at 4k after the fix d1cc7a4bd | PASS | Window / none / dense=15 / dense=15 + skip off: all d72631aab936fc4e |
| [P181](P181.md) | 2026-10-17 15:04-16:00 | T5 dense-layer screens on prose | Reported | 16k + even 4 dense 9/24 (886.9 s); 16k + last 4 5/24; 32k + even 4 10/24 (961.9 s); dense 11/24 |
| [P182](P182.md) | 2026-10-17 16:01-16:52 | T5 window 32k on n24 and code; prose 16k + first 4 dense | Reported (candidate) | n24 24/24 (814.3 s), code 19/24 (801.1 s), prose (P178) 9/24: 52/72 vs dense 54/72 at ~1.78x; f4 6/24 |
