# Index, P116 to P132

Run times are rig local time from receipts/queue.log. Events in this range (PR #40 and the device check,
bundle-20261013, D18 / D21 / D22 on the 4070, Cary's "sparse first" decision, the P118 root cause, product-sparse and
launcher PR #49, int8 bounds, patch 0055 = draft PR #56, the q3_0 port, the power cut and the crash) are in
`events-p109-p132.md`, E23-E37. P109b, P114 and P115 are in `index-p109-p115.md`. State at the time of writing:
2026-10-14 01:54, P124 running; queue order (notebook entry 06:43Z): P127, P133, P128, P129, P130, P131, P132, P125,
P119, P120. P133 (245k copies and needles on c8bbb1898: dense, sparse B 8192, sparse B 16384) is outside this range.
Next range: [`index-p133-p155.md`](index-p133-p155.md) ([P133](P133.md)).

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P116](P116.md) | 2026-10-13 16:57-17:08 | PR #40 (patch 0054, chunked GDN MMA prefill) on Turing | PASS | GATED_DELTA_NET 55/55; "not taken (shape or device)" once per server, 0 engaged; 32k 0053 vs 0054 within 0.2 % (decode 44.8 / 44.9 / 44.8 / 44.7) |
| [P116b](P116.md#p116b-the-merged-0054-de873117e) | 2026-10-13 18:26-18:33 | The merged 0054 (de873117e, device check first) on sm_75 | PASS | 55/55; "skipped: device cc 750 ..." once, 0 not taken / engaged; 32k prefill 344.9 vs 347.3, decode 44.8 vs 45.1 (within 0.7 %) |
| [P117](P117.md) | 2026-10-13 18:49-19:36 | HumanEval 164 with q3_0 K/V on the 8 GB 262k launcher | PASS | 160/164 (97.56 %), gate >= 157; failed 32, 39, 132, 145 (P87 q4_0: 158/164) |
| [P118](P118.md) | 2026-10-13 18:33-18:44 | Which op carries the always-on FA_SPARSE cost at 64k? | DONE (reading) | FLASH_ATTN_EXT 7.819 -> 22.822 ms per graph (+15.0 ms) with 0 sparse ops; root cause (4070): no prefetch for ops below MIN_HOST |
| [P119](P119.md) | queued (69m) | The P99 deep agent session on bundle-20261011 | OPEN (plan only) | Gate: all turns OK, 0 one-token, server alive, trace min free >= 60 MiB, no errors; per-turn walls vs P99 |
| [P120](P120.md) | queued (69n) | The P99 deep agent session with sparse | OPEN (plan only) | Rewritten twice before it ran: bin-sparse7 (margin 475, graphs off) -> bin-psparse (launcher c1908b7) -> bin-psparse8 (int8 bounds, launcher 8a47ffe) |
| [P121](P121.md) | 2026-10-13 19:36-20:17 | MIN_HOST crossover on the old build (3299a0b4b, line 34,560) | DONE (reading) | Sparse (MIN_HOST=0) 1.45x dense at 96k (23.0 vs 15.9), 1.78x at 128k (20.8 vs 11.7); crossover between ~18k and ~61k host cells |
| [P122](P122.md) | 2026-10-13 20:17-21:12 | product-sparse 3ab0af3c2: build, op tests, crossover with the launcher-sparse defaults | DONE (build PASS) | FA 3005/3005, GDN 55/55; line 62,464 -> 48,640 ("244 MiB of page bounds"); sparse 1.02x at 96k (25.0 vs 24.6), 1.17x at 128k (25.0 vs 21.3); min free 195 vs 70 MiB |
| [P123](P123.md) | 2026-10-13 22:40-23:03 | Routing-fix check: 64k default vs BONSAI_SPARSE=0, x2 | FAIL as written (routing fix confirmed) | 0 sparse ops at 64k; decode 34.5 vs 37.1 (-7.0 %; rounds -4.1 / -9.7 %) from the 13.8k shorter line; gate 2 % (4070 rule 5 %) |
| [P124](P124.md) | running from 2026-10-14 01:04 | Release-style sweep of product-sparse 3ab0af3c2 (launcher defaults) | OPEN (running) | Partial, def sweep: 52.8 / 47.4 / 35.2 / 27.0 / 26.0 at 4k-128k (floors from P126 - 3 %: 52.1 / 46.1 / 35.0 / 25.2 / 15.8); line 47,360; min free 171 MiB |
| [P125](P125.md) | queued (69il; was 69ie) | HumanEval 164 on product-sparse with the launcher-sparse defaults | OPEN (plan only) | Gate: >= 157/164 |
| [P126](P126.md) | 2026-10-13 21:12-~21:27 (cut); rerun 21:59-22:40 | Release check of bundle-20261013 (patch 0054) | FAIL as written at 64k-128k; release PASS via P126b | sha / tests / GDN skip line / 0 one-token / min free 112 PASS; 53.7 / 47.5 / 36.1 / 26.0 / 16.3 = -0.4 / -0.8 / -5.0 / -6.8 / -3.6 % vs P113; lookup_ab 22/22 texts as P113 |
| [P126b](P126.md#p126b-bundle-20261013-vs-bundle-20261011-in-one-session) | 2026-10-13 23:03-~23:56 (cut); rerun 10-14 00:10-01:04 | bundle-20261013 vs bundle-20261011 in one session, alternated x2 | PASS | 64k / 96k / 128k means 35.65 / 25.95 / 17.1 vs 36.0 / 26.0 / 16.85 (-1.0 / -0.2 / +1.5 %); cut run 38.3 / 27.5 / 17.7 vs 38.2 / 27.6 / 17.7 |
| [P127](P127.md) | queued (69if) | Build c8bbb1898 (int8 bounds) + 64k routing check x2 with launcher 8a47ffe | OPEN (plan only) | Gate: op tests; "VRAM line A -> B" ~7k above 48,640; 64k within 5 % of BONSAI_SPARSE=0 (2 % reported); 0 sparse ops at 64k |
| [P128](P128.md) | queued (69ig) | Release-style sweep of c8bbb1898 (int8 bounds) | OPEN (plan only) | Gate: 4k-128k >= P126 - 3 %; 160k / 245k >= 1.8x deep_off; min free >= 60 MiB every arm |
| [P129](P129.md) | queued (69ih) | Build q3-on-sparse 4dbfe57d4; q3_0 op tests and PPL (P108 set) | OPEN (plan only) | Gate: 0 FAIL in q3_0 cases; PPL q3_0 within 1 % of q4_0 at 16k / 64k and within noise of P108 |
| [P130](P130.md) | queued (69ii) | q3_0 at depth on 4dbfe57d4, sparse off (P114 set) | OPEN (plan only) | Gate as P114: line >= 1.2x; >= 1.05x at 128k / 192k; 4k within 3 %; needles 12/12, copies >= 9/10 |
| [P131](P131.md) | queued (69ij) | HumanEval 164 with q3_0 on 4dbfe57d4 (P117 set) | OPEN (plan only) | Gate: >= 157/164 |
| [P132](P132.md) | queued (69ik) | Sparse on (int8 bounds), q3_0 vs q4_0 at 160k -> 245k | OPEN (plan only) | Gate: q3_0 >= q4_0 at 160k and 245k; min free >= 60 MiB both arms |
