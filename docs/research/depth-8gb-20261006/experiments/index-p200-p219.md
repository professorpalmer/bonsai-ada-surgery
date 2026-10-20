# Index, P200 to P219

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records PR #177 and its
corrections, the kernel session's end of the T5 window work and the jump to P200, G1 on two cards and the 8 GB save step,
save after the answer from opt-in to default, the bundles 20261018 to 20261018f and their post-zip checks, the clock
tuning, replay rollback and draft 2 / 2 up to bundle-20261019b, research pass 2 and the sub-3-bit KV probe, the queue
incidents, the GPU time, the corrections and lessons) are in `events-p200-p219.md`, E96-E107. The previous range is
`index-p183-p188.md`.

Numbering: P189-P199 do not exist in this 2060 series. The 4070 kernel session used P188-P191 for its own runs
(`events-p183-p188.md` E92; E97 here), so this series jumped to P200 to keep every record number unique (notebook
2026-10-18 00:55 CDT).

State at the time of writing: 2026-10-19 19:11 CDT by the rig clock (2026-10-20 00:11Z). The last notebook entry in this range is
"18:39 CDT Cary: "do the records, then wait for the bundle". Records agent writes P200-P219 (worktree bas-rec6) ...". The
queue is empty and filler a runs (from 18:35:35). bundle-20261019b (replay on + draft 2 / tail 2 on 8 GB) was published at
22:15:39Z (17:15 CDT); the formal R6 post-zip check on it and the quick_tps sweep that the release session asked for
(22:16:16Z) have not run. Cary's wrap-up (22:46:32Z) closes #138 after R6 and P219; P219 is posted (22:46:41Z).

Decisions in this range: the 8 GB preset saves every 4096 tokens (PR #182, from P200); save after the answer is the
default from bundle-20261018b (the release session, on the 4070's runs 7-8; P204 / P205 as the 8 GB data); slot 3 (215 W
+ core +100) is an optional serve step, not a default; slot 4 (+150) is out; the 8 GB preset defaults to replay rollback
+ draft 2 / tail 2 from bundle-20261019b (P213-P217 and the 4070's AD1-AD3); KV below 3 bits is closed (P216, P219). My
mistake: P204 ran at GROW 8192 (E99).

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P200](P200.md) | 2026-10-18 05:13-06:32 | G1 on the 2060: layer cache save step 4096 vs 8192, P164 session | PASS; adopted (#182) | Restart turns 109.8 -> 56.5 s (-48.5 %), normal +8.8 %, session -18.7 %, 30/30 equal; the 4070: +50 % |
| [P201](P201.md) | 2026-10-18 06:32-07:37 | Power limit 215 W (slot 1) on cold reads | PASS; not adopted | 64k +1.8 %, 240k +1.3 %; +30 W, +7 C; SM clock unchanged (V-F curve) |
| [P202](P202.md) | 2026-10-18 07:38-08:42 | 215 W + core +100 (slot 3) on cold reads | PASS | 64k +5.9 %, 240k 1,348.4 vs 1,416.8 s (+5.1 %), decode +3-5 %; SM 1,965 MHz; 79 C |
| [P203](P203.md) | 2026-10-18 08:43-09:25 | Slot 3 soak: P200's 30-turn session (GROW 8192) | PASS | 30/30 answers = P200 stock; max 77 C, 214 W; 2,173 vs 2,266 s (at a lower line) |
| [P204](P204.md) | 2026-10-18 09:25-10:50 | Save after the answer A/B on bundle-20261018, at GROW 8192 (my mistake) | A, C-F PASS; B FAIL | Restart turns -6.2 %, normal +6.9 %, session -0.6 %, 30/30; the layer did not get GROW 4096 |
| [P205](P205.md) | 2026-10-18 10:51-12:02 | Save after the answer at GROW 4096 | A, C-F PASS; B FAIL | Restart 57.2 -> 54.1 s (-5.4 %), session -2.3 %, 30/30; save-after became the default in 18b |
| [P206](P206.md) | 2026-10-18 12:03-12:08 | Post-zip check of bundle-20261018 (not asked) | PASS | det 4k = 17b; cold 64k 308.2 tok/s; 0 CUDA errors |
| [P207](P207.md) | 2026-10-18 12:10-12:59 | 215 W + core +150 (slot 4) on cold reads | Gates PASS; long read slow | 64k +8.3 %; 240k 1,937.5 s (stock ~1,417); GPU waits past ~125k |
| [P208](P208.md) | 2026-10-18 15:25-16:18 | Slot 4 long read again, stock in-block, CPU logged | Reported; slot 4 out | 1,574.3 vs 1,505.8 s; CPU mean 9 %; stock varies 1,417-1,506 s |
| [P209](P209.md) | 2026-10-18 16:20-16:42 | Post-zip check of bundle-20261018c (delta saves; asked) | PASS | det 4k = 18b; 64k 307.4; 12/12 = P205; deltas 0.45-0.49 s, ~271 MB; 3/3 chain restores |
| [P210](P210.md) | 2026-10-18 18:56-19:13 (first try 18:55, failed) | Optional check of bundle-20261018d, `BONSAI_SLOT_CACHE_AFTER=0` | PASS | 12/12 = P205 after=0; saves before the request are deltas (0.45-0.49 s) |
| [P211](P211.md) | 2026-10-19 01:08-01:25 | Post-zip check of bundle-20261018f (not asked) | Reported | Deltas after every answer 0.37-0.41 s; restores 2.6-4.2 s; 10/12 = P205 (4, 10: whitespace); turn 7 34.1 vs 60.1 s |
| [P212](P212.md) | 2026-10-19 01:26-01:42 | The 2060 cache-off reference for the 12-turn session | PASS | P211 (18f) = cache-off 12/12; P205 10/12 |
| [P213](P213.md) | 2026-10-19 06:36-07:42 (first try 06:13, failed) | R6 groundwork: replay rollback (patch 0070) on the 2060 | PASS | Identity at pinned 80,640; line 80,128 -> 90,624; decode 128k 23.0 -> 26.2 (+13.9 %); soak 0 errors |
| [P214](P214.md) | 2026-10-19 07:43-08:20 | Replay rollback at 200k | Reported | Decode 12.6 -> 12.9 (+2.4 %); prefill 187.2 -> 188.2; min free 95 -> 109 MiB |
| [P215](P215.md) | 2026-10-19 08:22-09:21 | Draft size with replay: 1/1, 2/1, 2/2, 3/3 | Reported | 2 / 2: 55.6 / 41.3 / 31.8 tok/s at 4k / 64k / 128k (+21.8 % at 128k) for 512 cells |
| [P216](P216.md) | 2026-10-19 09:21-11:33 | Full 2-bit KV (fake bits): rotation, Lloyd-Max | FAIL (G1) | Best: uniform + rotation 64k +1.83 %, 16k +3.07 % vs q3_0; P100 had rotation on |
| [P217](P217.md) | 2026-10-19 12:25-13:46 | Quality gate for draft 2 / 2 (P170 code set, rounding null) | PASS | d11, null and d22 all 21/24; 0 confident wrong, 0 changes |
| [P218](P218.md) | 2026-10-19 11:33-12:25 | V-only 2-bit KV (K q4_0) perplexity | PASS (G1) | 64k 7.2491 (+0.55 %), 16k +1.16 % |
| [P219](P219.md) | 2026-10-19 13:46-16:35 | G2 for V-only 2-bit: n24 at 245k + the P170 code set | FAIL | 2 confident wrong where q4_0 is right (needle 14, code 15) vs 0 for the null; sub-3-bit KV closed |
