# Index, P162 to P168

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (the records-review corrections and
PR #163, release-0062 and bundle-20261017, the PR #159 review and merge, the serve folder serve-1017, the T4-A fast-read
plan and the first 4070 numbers, the spill guard PR #164 from v2 to v5 and the forward-slash fault, the VRAM line
86,784) are in `events-p162-p168.md`, E67-E75. The previous range is `index-p156-p161.md`.

State at the time of writing: 2026-10-17 05:20 CDT by the rig clock (10:20Z). The last notebook entries in this range are "05:00
CDT P168 result ..." and "05:04 CDT VRAM line 86,784 vs 80,640: explained (no fix)". The next entry, "05:09 CDT P169
queued: T4-A fast read on the 2060", is outside this range (P169 started 05:09:18). PR #164 (the spill guard) is open.

P166, P166b and P167 are void as tests of the spill guard: BONSAI_BIN had forward slashes and the guard never found the
server (notebook correction 03:15 CDT). Their card data stands. P167b is the valid G4 run.

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P162](P162.md) | 2026-10-16 22:21-22:41 | Read ahead (T1-d, `prefill_only`) on bin-0060p: 131k, restart, ask | PASS | 130,452 tokens saved (563.8 s) + .draft 15,011,460 B; restart + ask 6.25 s (restore 1.84 s, prompt_n 39) = cold control (560.7 s); 0 CUDA errors |
| [P163](P163.md) | 2026-10-16 22:41-23:10 | Post-zip check of bundle-20261017 (release-0062 S7) + S1 restore on the zip bins | PASS (no 131k restore) | sha / 0 control bytes / 96f6e49cdc / op tests; cold 128k 529.28 s; 4k 53.4, 64k 41.2; restores 227.34 / 227.68 tok/s, 0 CUDA errors |
| [P164](P164.md) | 2026-10-17 01:37-02:19 | Soak of the served bundle: 30 turns ~131k to ~250k, restart every 3rd turn | PASS (restart gate as read) | 30/30, 0 empty / one-token / CUDA errors, min free 99 MiB; non-restart 26.9-44.0 s; restart turns 85-132 s (restore 2.05-3.36 s + re-read ~12k + save) |
| [P165](P165.md) | 2026-10-17 02:19-02:39 | The demo clip on the served bundle (199k read ahead, restarts, 3 questions) | PASS | Read ahead 1,068.6 s; restart + Q1 first token 5.3 s (wall 11.8 s); Q2 2.6 s, Q3 2.5 s; second restart 7.3 s; Q2 answer wrong (thinking off) |
| [P166](P166.md) | 2026-10-17 02:39-02:53 | Spill guard G4 (v2 5edcfe7): G4a cold 128k, G4b (free - 100) hog | VOID as a guard test | Guard never ran (forward-slash BONSAI_BIN). Card: 128k 530.77 s; a 182 MiB hog halved the 16k read (198.7 tok/s) |
| [P166b](P166.md#p166b) | 2026-10-17 02:54-02:55 | Spill guard G4b with a 1,500 MiB hog | VOID as a guard test | Guard never ran. Card: the next read crashed with CUDA out of memory (2 error lines) |
| [P167](P167.md) | 2026-10-17 02:57-03:11 | Spill guard v3 (c345b33): small hog, 1,500 MiB hog, cold 128k | VOID as a guard test | Guard never ran. Card: 16k 230.3 tok/s with a 199 MiB hog; 1,500 MiB crash; 128k 529.75 s |
| [P167b](P167.md#p167b) | 2026-10-17 03:13-03:33 (first start 03:11-03:13 FAILED) | Spill guard v4 (02523b9), Windows-form BONSAI_BIN: the valid G4 run | PASS | 206 MiB hog -> the line (379 MiB / 133 free) before the read, 16k 70.1 tok/s; 1,500 MiB -> the line (1,673 / 119), then crash; 128k 529.21 s, 0 lines |
| [P168](P168.md) | 2026-10-17 03:54-04:57 | Spill guard v5 (7e4ac46) G5 soak: 1 h, display + Edge video + WebGL on the 2060 | PASS (64k +2.2 % faster than the band) | 0 lines in the hour; 128k 239.2 tok/s, 64k 309.3-309.6 x3; 18 MiB end hog -> the line; min free 86; line 86,784 = free VRAM at start |
