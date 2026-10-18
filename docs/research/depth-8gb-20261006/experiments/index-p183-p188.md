# Index, P183 to P188

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records PR #173 and its
corrections, the T5 release gates on the 4070 and the T5 hold, PR #171 with the G2 ask I missed and its hold, the
offline scoring of wrong answers where dense is right, the off-vs-off tests on both cards and the 4070 rounding null
test, the GPU time, the corrections and lessons) are in `events-p183-p188.md`, E88-E95. The previous range is
`index-p169-p182.md`.

State at the time of writing: 2026-10-17 22:35 CDT by the rig clock (2026-10-18 03:35Z). The last notebook entries in
this range are "22:22 CDT P188: dense code + prose again = P170 exactly (0 items differ); ..." and "22:27 CDT 4070
rounding null test (GGML_CUDA_FA_CHUNK=16384, window off): 1 item changes vs 7 for the window: T5 hold stands". The
next entry, "22:30 CDT Kernel session P189 plan (4070) ...", is outside this range; it says the next 2060 experiment
is P190 (the kernel session uses P188 / P189 for 4070 runs). The queue is empty and filler c runs (from 22:21:50). T5 is held (Cary, #138 00:23:31Z) and stays on the fork
(`t5-window-emu` d1cc7a4bd; `release/t5-candidate` a6bfcb1a4f); the kernel session plans its P189 (a drift score) on
the 4070. PR #171 (the 8 GB pool reserve) is held as a draft (Cary, 02:03:35Z). No bundle is planned.

Decisions in this range: T5 does not ship (the R2 wrong-answer clause failed on the 4070: 3 confident wrong answers,
limit 1); #171 does not ship (G3 failed on the 2060: with the display on the card the squeeze is WDDM demotion, not
pool growth). My miss: the #171 G2 ask waited ~7.5 h (E90).

The kernel session also used the label "P188" for its 4070 null test. In these records P188 is the 2060 dense rerun;
the kernel session's run is "the 4070 rounding null test (comment 6245174745)".

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P183](P183.md) | 2026-10-17 16:53-17:54 | T5 noise floor (dense prose again, window-32k prose again) and window 32k at 128k | Reported | Dense 11/24 (4 items flip vs P170, other settings); w32 9/24 = P178 on all 24 answers (808.9 s, 1.76x); 128k 414.3 s (1.29x), n24 at 128k 23/24 |
| [P184](P184.md) | 2026-10-17 17:56-18:26 | T5 window 32k in the P164 agent soak (30 turns, 131k -> 250k, restarts) | PASS | 30/30 answers = P164; 1,504.4 vs 2,272.6 s (1.51x); normal turns 1.34x -> 1.59x, restart turns 1.53x -> 1.84x; line 86,528 (P164 ~80k) |
| [P185](P185.md) | 2026-10-17 18:26 (builds 17:57-18:11) | Turing MMQ table for PTQ1_0 (fork `turing-mmq` 7d262ec31), two variants | Negative | Occupancy 2 24.83 TFLOPS vs zip 28.42 (-12.6 %); I 64 illegal memory access; no server runs |
| [P186](P186.md) | 2026-10-17 18:28-18:43 | PR #171 G2 on the 2060: the 8 GB pool reserve (zip 17b + PR head 5125d445) | G1, G2, G4 PASS; G3 FAIL | "pool reserved 176 MiB"; 128k 241.1 tok/s (+0.8 %), min free 112 MiB; 163 MiB ballast -> 16k 61.2 vs 388.4 tok/s; #171 held |
| [P187](P187.md) | 2026-10-17 18:45-19:29 | T5 window 32k + 8 dense layers (7:15:...:63) on the P170 sets | Reported | Code 21/24 (0 wrong where dense is right), prose 10/24 (1 wrong: 22; 2 against one dense run); 1.28x; fails on the 4070 |
| [P188](P188.md) | 2026-10-17 21:28-22:21 | Dense code + prose again (zip bins, the P170 recipe): off vs off on the 2060 | Reported | 0 items differ from P170 (48/48, first 60 characters equal); cold 1,405.9 / 1,419.8 s |
