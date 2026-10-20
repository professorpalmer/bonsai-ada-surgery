# Index, P220 to P223

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records PR #215 and its corrections
post, the formal R6 of bundle-20261019b, the P222 decision (option B), bundle-20261019c and its post-zip check, the
close of #138, the try-1 incident, the GPU time, the corrections and lessons) are in `events-p220-p223.md`, E108-E116.
The previous range is `index-p200-p219.md`.

State at the time of writing: 2026-10-20 13:45 CDT by the rig clock (18:45Z). The last notebook entry in this range is
"2026-10-20 08:57 CDT bundle-20261019c (release 22:41 CDT; option B on #138, issue closed): P223 post-zip check PASS".
#138 is closed (03:41:33Z). bundle-20261019c is the latest release. The queue runs 69jeci (P224, a demo dry run) from
13:39:59; it is in the next range.

Decisions in this range: the formal R6 of bundle-20261019b passes on correctness and the soak but fails the speed gate
below the VRAM line (P220, P221); the release session chose option B on P222 (replay + draft 1 / tail 2 as the 8 GB
default) although P222's declared gate failed, and shipped it in bundle-20261019c; P223 confirms the zip; #138 closed.

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P220](P220.md) | 2026-10-19 19:15-20:46 | Formal R6 of the bundle-20261019b zip: launcher, quick_tps sweep 4k-245k, 30-turn soak | Gates 1, 3, 4 PASS; speed gate FAIL | 51.7 / 39.1 / 29.1 / 18.6 / 11.4 tok/s; 4k -3.2 %, 64k -5.1 % vs the cards; soak 30/30 = P200, 1,631 s; 0 CUDA errors |
| [P221](P221.md) | 2026-10-19 20:47-21:10 | In-block A/B: default (replay + 2 / 2) vs `BONSAI_RS_REPLAY=0` (1 / 1), ABAB x2 | FAIL | 4k 51.9 vs 53.65 (-3.3 %), 64k 39.1 vs 40.6 (-3.7 %); acceptance 0.62 vs 0.78 |
| [P222](P222.md) | 2026-10-19 21:11-21:59 | Replay + draft 1 / tail 2 vs 2 / 2 vs 1 / 1 at 4k / 64k / 128k | Declared gate FAIL; option B shipped | d12 / def / old: 4k 52.4 / 51.9 / 53.7, 64k 39.9 / 39.0 / 40.6, 128k 29.6 / 29.7 / 22.4 |
| [P223](P223.md) | 2026-10-20 08:45-08:57 (try 1 08:43-08:44, HTTP 401) | Post-zip check of bundle-20261019c | PASS | Spec "draft 1 (2 past the VRAM line)"; 4k 52.6, 128k 29.1 (within 2 % of P222 d12); 0 CUDA errors |
