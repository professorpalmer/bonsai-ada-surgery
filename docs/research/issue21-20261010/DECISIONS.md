# Decisions in issue #21

Every decision the thread made, in time order, with the comment that made it (`THREAD.md`, C##) and the record that
holds the numbers. Times are UTC. "4070" = the engine / release sessions on the RTX 4070 12 GB; "2060" = the 8 GB
tester on the RTX 2060 SUPER. Records: `../depth-8gb-20261006/experiments/P###.md` (2060), `../depth-20261010/`
(D##), `../release-20261013/` (G##), `../release-20261014/` (R##), `../release-20261014b/` (S##), `../q3port-20261013/`
(Q##, D27 / D28).

| # | when (UTC) | decision | why | where |
| --- | --- | --- | --- | --- |
| 1 | 10-10 19:36 | Split the work: the engine is built on the 4070, depth tests run on the 2060 | Each card does what it is best at: the 4070 builds and op-tests fast, the 2060 is the real 8 GB case | C00, C01 |
| 2 | 10-10 23:49 | Quality of sparse reads is settled; the work moves to speed | P101: about 4 % of the host tail at 245k gives the same copies and needles as dense | C04-C06 |
| 3 | 10-11 01:35 | Page selection moves to the device; host syncs go | On `87e2ac160` each attention op copied to the host and synced, so the read path could not show its speed | C08-C13 |
| 4 | 10-11 06:14 | The MMA tile map is the speed path | Without it, MMA reads every masked host tile over PCIe (slower than dense); with it, 2.2x dense at a 127k-cell host tail | C14, C15 |
| 5 | 10-11 08:18 | Page 64, not 256 | Page 256 was faster but missed one exact copy; page 64 was 2x dense with copies and needles equal | C16, C17, P105 |
| 6 | 10-11 15:48 / 10-13 16:02 | Count the sparse allocations in the VRAM line | Every sparse arm over-committed VRAM (`memory.free` wrapped); WDDM spilled buffers to system RAM | C24-C27, P109, D18 |
| 7 | 10-13 19:36 | `MIN_HOST=32768`: dense below about 32k host cells | Sparse costs time on a short host tail; P112 showed 2.15x at 160k but -20 % at 64k | C31, C32, P111, P112 |
| 8 | 10-14 00:49 | Ship sparse first, q3_0 in a later bundle (Cary) | Sparse was nearly ready; q3_0 needed a rebase onto the sparse attention code | C40-C42 |
| 9 | 10-14 00:53 | Routing fix: one eligibility check for the sparse mask and the prefetch | P118: below `MIN_HOST` an op got no sparse mask and no prefetch, and read the whole host tail in place (7.8 -> 22.8 ms per graph) | C36, C41 |
| 10 | 10-14 02:22 | int8 page bounds (514 B per host cell, was 1 KiB) | Half the VRAM line cost, same selection (D22) | C49, C54 |
| 11 | 10-14 08:55 | Budget grows with depth: max(12,288 cells, host tail / 16) | B 8192 missed one exact copy at 245k on both cards (D22c, P105); per-head ranking did not fix it (D23) | C59-C63 |
| 12 | 10-14 12:12 | Sparse is opt-in (`BONSAI_SPARSE=1`) in bundle-20261014 | int8 halved the line cost, but 64k was still -8 % (P127): any reserve that moves the line below 64k costs speed | C66-C68 |
| 13 | 10-14 13:16 | Launcher headroom for sparse 36 -> 64 MiB | A 245k VRAM trace measured 150 MiB against 138 counted | C71, C72 |
| 14 | 10-14 13:06 | Driver 591.86 -> 610.88 is neutral; A/Bs continue on 610.88 | P134: the same binaries within noise on both drivers | C64, C70 |
| 15 | 10-14 20:02 | The 64k cost is the line (a step), not engine overhead | P137 / D26a: no cost from the engine; any host tail versus none is the step. Path to default-on: bounds that take no line (D26) | C74, C79 |
| 16 | 10-14 20:18 | The q3_0 8 GB default rule, written before the 2060 runs | 64k within 5 % of q4_0, perplexity at 16k <= +1 %, HumanEval >= 157, copies and needles = q4_0; else opt-in (#84) | C80, C81 |
| 17 | 10-14 20:45 / 21:10 | The 2060 q3_0 set runs on `product-0056` `b86298dba` (with 0057) | Test the engine the bundle ships, not an earlier build | C82-C86 |
| 18 | 10-15 03:57 | A wider item set for the shipped sparse rule (R10 on the 4070, P141 on the 2060) | On another model, FRAC 1/16 missed one needle digit at 245k; FRAC 1/8 was right | C91 |

## Releases from the thread

| bundle | what | 2060 check |
| --- | --- | --- |
| bundle-20261011 | patch 0053, CUDA graphs off past the line | C29 |
| bundle-20261013 | patch 0054, chunked gated-delta-net prefill | P126 / P126b (C46) |
| bundle-20261014 | patch 0055, sparse host-tail reads, opt-in | P135, P136, P138, P139 (C73, C76, C87, C88) |
| next (0056 + 0057) | q3_0 K/V, packed-half dequant | P129 PASS, P130 partial PASS (C89, C90); P140, P131, P132 running |
