# Experiments

One entry per run. Times are local. Decode is tok/s, the mean of the greedy and the temperature 0.8 request; in
brackets the draft acceptance (`draft_acc / draft_n`, MTP and lookup together). Analysis: `receipts/analyze.py
receipts/ab.jsonl`.

## AD1: F1 against adaptive A4 and A3

- When: 2026-10-19 09:18-11:15, 1.94 GPU-h. Receipts: `receipts/ab.log`, `receipts/ab.jsonl` (72 records).
- 0 CUDA errors in all arms; every request answered (G3 pass).

Code:

| depth | F1 | A4 | A3 |
| --- | ---: | ---: | ---: |
| 4k | 82.7 (69 %) | 84.3 (55 %) | 85.4 (55 %) |
| 32k | 77.7 (72 %) | 75.6 (52 %) | 72.1 (47 %) |
| 64k | 73.3 (78 %) | 73.8 (57 %) | 77.0 (59 %) |
| 128k | 33.6 (74 %) | 39.9 (50 %) | 39.0 (53 %) |
| all depths | 66.8 | 68.4 (+2.3 %) | 68.4 (+2.3 %) |

Story:

| depth | F1 | A4 | A3 |
| --- | ---: | ---: | ---: |
| 4k | 75.6 (55 %) | 72.6 (42 %) | 75.5 (45 %) |
| 32k | 69.0 (48 %) | 63.9 (37 %) | 65.9 (38 %) |
| 64k | 63.6 (56 %) | 57.6 (37 %) | 60.0 (41 %) |
| 128k | 29.7 (59 %) | 31.9 (42 %) | 30.7 (40 %) |
| all depths | 59.5 | 56.5 (-5.0 %) | 58.1 (-2.4 %) |

Quote (copy a record from the context):

| depth | F1 | A4 | A3 |
| --- | ---: | ---: | ---: |
| 4k | 111.5 (61 %) | 115.4 (59 %) | 136.9 (75 %) |
| 32k | 101.1 (65 %) | 106.5 (72 %) | 114.6 (76 %) |
| 64k | 87.2 (71 %) | 88.1 (68 %) | 103.7 (73 %) |
| 128k | 37.3 (74 %) | 53.6 (61 %) | 58.8 (82 %) |
| all depths | 84.3 | 90.9 (+7.9 %) | 103.5 (+22.8 %) |

- G1 FAIL: code +2.3 % for both adaptive arms (5 % required).
- G2 FAIL: the worst story depth is 64k, A4 -9.4 %, A3 -5.6 % (3 % allowed).
- G3 pass.
- Verdict: **not adopted.** The controller also climbs on prose and then misses: story acceptance falls from 48-59 % to
  37-45 %, and each miss costs a verify column.
- What helps: past the VRAM line (128k) the step is PCIe-bound, so extra verify columns are nearly free: code +16-19 %,
  quote +44-58 %. Copy text gains at every depth (A3 +23 %), the case the controller is made for.
- Greedy text equal to F1: A4 2 / 12, A3 3 / 12 requests. A different draft size changes the greedy text through
  rounding (the batch shape of the verify step changes), as P215 also saw on the 2060.
- Log note: the "depth changes" count in `ab.log` is 0 and not valid. The depth-change line is a debug line, and log
  verbosity 4 does not print it. The server log shows `adaptive MTP draft depth: 1 .. 4`, and A4 drafts more tokens per
  request than F1 (first request 311 against 179).

## AD2: fixed draft 2 / 2 (F2) on the same bins

- When: 2026-10-19 11:15-11:54, 0.65 GPU-h. Line 90,112 (the P215 line on the RTX 2060 SUPER). 0 CUDA errors; every
  request answered. Receipts: the same `receipts/ab.log` / `ab.jsonl` (tag F2).

| depth | code F1 | code F2 | story F1 | story F2 | quote F1 | quote F2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4k | 82.7 | 89.0 (+7.6 %) | 75.6 | 78.8 (+4.2 %) | 111.5 | 115.6 (+3.7 %) |
| 32k | 77.7 | 81.0 (+4.2 %) | 69.0 | 69.9 (+1.3 %) | 101.1 | 116.2 (+14.9 %) |
| 64k | 73.3 | 69.6 (-5.0 %) | 63.6 | 61.6 (-3.1 %) | 87.2 | 97.6 (+11.9 %) |
| 128k | 33.6 | 40.2 (+19.6 %) | 29.7 | 30.8 (+3.7 %) | 37.3 | 46.7 (+25.2 %) |
| all depths | 66.8 | 69.9 (+4.6 %) | 59.5 | 60.3 (+1.4 %) | 84.3 | 94.0 (+11.6 %) |

- F2 is the best balance of the four arms: no prompt type loses over all depths, and the 128k gain matches P215 on
  the 2060 (code at 128k +21.8 % there, +19.6 % here). The weak depth is 64k (code -5.0 %, story -3.1 %).
- Greedy text equal to F1: 3 / 12 (the rounding effect, as in AD1).
- Verdict: supports P215's proposal (2 / 2 as the 8 GB default with replay). The default change waits on the quality
  gate on the 2060 (P164 / G1 and the P170 code set, in #138).
- Consequence for the draft vocab shortlist: with 2 / 2, each token takes two MTP draft steps, and each step reads the
  full 248k-row output head. A shortlist head saves that read twice per token, so the shortlist is the next item.
