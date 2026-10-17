# Index, P133 to P155

Run times are rig local time (CDT) from receipts/queue.log. Events in this range (driver 610.88, the 4070's FRAC /
opt-in decisions and the RC, bundle-20261014 / 20261015 / 20261015b / 20261015c / 20261016, the q3_0 set and the 0056
rule, R10 and FRAC 1/8, #21 closed and #105 opened, the launcher bug and PR #108, D26g and D26h, Cary's card decision
and PR #142, the missed 4070 posts, the P146 false starts, issue #138 and the cold read-in plan, T1 slot save / restore)
are in `events-p133-p155.md`, E38-E56. The previous range is `index-p116-p132.md`.

State at the time of writing: 2026-10-16 after 08:10 (last notebook entry "08:10 CDT T1-c v2 ..."), P155 running;
pending: P155b, P156, P152, P149b (queue 69jea7, 69jea8, 69jeb, 69jf). P156 (T2a-2 quality gates on bin-t2) is outside
this range.
Next range: [`index-p156-p161.md`](index-p156-p161.md) ([P156](P156.md)); the P155 / P155b rows below were updated
with their results.

Results of earlier-range runs that finished in this time span are in the notebook, not in their records (which stay
"plan only" in `index-p116-p132.md`): P127 (entry "P127 (result): int8 bounds ..."), P129, P130, P131 (entries "P129
(result)", "P130 (partial / result)", "P131 (result)"), P132 (stopped partial, entry "06:58 P132 stopped ..."), P128 and
P125 (superseded, entry "~07:15 (local) the 4070's overnight decisions ..."), P124 (partial, entry "02:29 Windows
Update restart ..."). P119 and P120 ran 2026-10-15 14:05-15:43 (queue log) with no result entry in the notebook.

| ID | date | title | status | one-line result |
| --- | --- | --- | --- | --- |
| [P133](P133.md) | not run (plan 10-14 06:43Z) | 245k copies / needles on int8 bounds: dense vs B 8192 vs B 16384 vs B 8192 + NORM | SUPERSEDED | Answered first on the 4070 (D22c: B 12288 / 16384 10/10; D23 NORM 9/10, NORM out); replaced by the RC checks P135 / P136 |
| [P134](P134.md) | 2026-10-14 07:08-08:05 | Driver 610.88 baseline: bundle-20261013 vs 20261011 in one session | PASS | Means 1011 37.7 / 27.25 / 17.6, 1013 37.75 / 26.45 / 17.8 at 64k / 96k / 128k; = 591.86 at the same line; the spread follows the line |
| [P135](P135.md) | 2026-10-14 08:05-09:48 | RC 4de618549 + #49: build, op tests, 160k / 245k dense vs BONSAI_SPARSE=1 | PASS (amended 160k gate) | FA 3005/3005, GDN 55/55; 160k 17.5 vs 10.6 (1.65x), 245k 13.7 vs 6.3 (2.17x); min free 153 MiB |
| [P136](P136.md) | 2026-10-14 09:48-14:31 | RC copies / needles at 160k / 200k / 245k, dense vs sparse | PASS | All 10/10 + 12/12 in both arms at every depth; 0 misses |
| [P137](P137.md) | 2026-10-14 14:31-15:01 | D26a on Turing: line cost or engine overhead at 64k? | DONE (reading) | off_short 35.4 / 35.4, on_short 35.5 / 35.4, off_long 36.4 / 36.3: overhead +0.1 %, line cost -2.6 % |
| [P138](P138.md) | 2026-10-14 15:01-16:36 | Post-zip check of bundle-20261014 (default switches) | PASS | sha / tests / commit 4de6185494; same-session vs 1013 -0.8 / -0.2 / -0.6 %; sweep 53.6 / 47.8 / 36.5 / 26.2 / 16.2; min free 117 |
| [P139](P139.md) | 2026-10-14 16:36-19:28 | bundle-20261014 zip bins: 245k sparse, copies / needles, HumanEval | PASS | 245k 13.6 vs 6.2 (2.19x), min free 153 / 106; 10/10 + 12/12; HumanEval 158/164 |
| [P140](P140.md) | 2026-10-14 23:26-10-15 00:25 | S05: q4_0 default unchanged by 0056 + 0057 | PASS | Answers 11/11 identical x4; 64k 39.6 / 39.7 vs 35.7 / 35.6 (+11.2 %), 128k 16.9 vs 15.7 (+7.6 %) |
| [P141](P141.md) | 2026-10-15 00:25-05:24 | R10 on the 2060: wider items at 245k, FRAC 1/16 vs 1/8 | PASS (amended #95 rule) | dense 20/20 + 24/24; 1/16 20/20 + 23/24 (needle 0.271); 1/8 20/20 + 24/24; 1/8 1.59x / 1.76x |
| [P142](P142.md) | 2026-10-15 06:59-08:15 | Post-zip check of bundle-20261015 (q3_0 default) | FAIL (release bug) | Default launcher never picks q3_0: backspace bytes in the `$HasQ3` pattern; q4_0 ran (line 61,696); tests pass; fix PR #108 |
| [P143](P143.md) | 2026-10-15 08:20-11:27 (first start 08:15, stopped) | D26g: BONSAI_SPARSE=1 as the 8 GB default with q3_0 | FAIL | 80k -6.7 %, 96k -3.0 %, 112k -18.5 % (gate 2 %); deep 1.34x / 1.44x; MIN_HOST 64k arm 24.7 / 19.3 / 20.6 |
| [P144](P144.md) | 2026-10-15 11:52-14:05 | The card's quality receipt: 245k code n 20 / needles n 24, shipped setup | PASS | dense 20/20 + 23/24, sparse 20/20 + 23/24, the same miss (vault 14, 0.562) |
| [P145](P145.md) | 2026-10-15 11:27-11:52 | Post-zip check of bundle-20261015b (launcher fix) | PASS | 0 control bytes; q3_0, line 80,128; 53.2 / 40.8 / 22.7 vs P130 53.6 / 41.1 / 22.8; fresh 60k 40.0 |
| [P146](P146.md) | 2026-10-15 19:08-23:38 (tries 1-2 18:54-19:08) | D26h on the 2060: auto vs off, the #105 merge gate | PASS (G1-G4) | r2 auto / off: 112k -1.5 % (worst), 160k +2.6 %, 245k +10.1 %; det answers identical; min free >= 71; calib key mismatch (line moves 512 cells) |
| [P147](P147.md) | 2026-10-15 18:34-18:54 | Post-zip check of bundle-20261015c (patch 0058) | PASS | 0 control bytes; c2cf6d6450; q3_0, line 80,640; 4k 53.3, 64k 40.6; min free 111 |
| [P148](P148.md) | 2026-10-15 23:38-10-16 02:56 | 245k quality with auto choosing sparse: code n 20, n 24, n 28 | PASS | auto = dense: 20/20, 23/24, 27/28, the same misses (vault 14, vault 15); auto kept 668 of 2675 pages |
| [P149](P149.md) | 2026-10-16 02:56-03:28 (stopped by plan) | FRAC 1/8 forced at 245k, n 28 | DONE (n 28): = dense | 27/28, miss vault 15 only (= P148 dense); vault 16 correct (the 4070 lost it): the rigs disagree |
| [P149b](P149.md#p149b) | pending (queue 69jf) | FRAC 1/8 forced at 245k, n 24 and code n 20 | OPEN (plan only) | Rule: 1/8 = dense on all sets -> look closer; 1/8 loses an item dense keeps -> 1/4 stands |
| [P150](P150.md) | 2026-10-16 03:28-04:34 | Post-zip check of bundle-20261016 (q3_0 + automatic sparse) | PASS | 0 control bytes; ab94810051; line 80,384, auto; 54.0 / 41.1 / 22.3 / 16.7 / 9.8 at 4k-245k; cold 245k 1,696 s; min free 71; card PR #142 merged |
| [P151](P151.md) | 2026-10-16 05:54-06:25 | Cold 245k prefill op-time profile | DONE (reading) | Time-weighted FA 65.3 %, MUL_MAT 25.2 %, GDN 4.1 %, other 5.4 %; ttft 1,697 s; fixed floor ~10 min at 245k |
| [P152](P152.md) | pending (queue 69jeb) | BONSAI_CTX 131k vs 262k at 4k-128k | OPEN (plan only) | Rule: 262k within 2 % of 131k at every depth -> "the full window costs nothing up to 128k" |
| [P153](P153.md) | 2026-10-16 06:25-07:24 | T1-b on the 2060: slot save, restore on a fresh server, continue | PASS (G1-G4) | B2 == D2 at 64k / 131k / 245k; restore + prompt 1.85 / 2.75 / 5.23 s (cold 229.6 / 611.4 / 1,688.9 s); thinking on: full re-read (234.36 s) |
| [P154](P154.md) | 2026-10-16 04:34-05:54 | T2a on sm_75: NCOLS2=2 prefill attention | DONE | 4k answers identical; cold TTFT 64k 221.2 -> 207.2 s (1.067x), 128k 589.1 -> 530.8 s (1.110x); decode same |
| [P155](P155.md) | 2026-10-16 07:24-08:22 | T1-c: automatic saved conversations in the layer | FAIL (engine crash after restore; result added later) | R1 = M1, 4k unchanged; R2 crashed after the restore at 131k + ~4k (ggml-cuda.cu:109); thinking on: no restore (v1 save point) |
| [P155b](P155.md#p155b) | 2026-10-16 08:22-09:39 | T1-c v2: save before the generation prompt, n_saved from the server | Layer PASS, engine FAIL (result added later) | n_saved 130,480 / 65,604; answers = memory, E3, S; R4 / RT2 crashed after a restore; R2 read at 12.27 tok/s |
