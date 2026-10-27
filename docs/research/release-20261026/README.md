# Release bundle-20261026 (faster attention at depth: the quantized K/V tiles load ahead)

Plan written before the runs. Engine: `serve/qkv-prefetch` (`a38714c63d`) = bundle-20261025's engine `810d93e5aa` +
patch 0072. Launcher, layer and suite: unchanged.

Patch 0072: in the tensor-core flash-attention kernel, with a quantized K/V cache (q4_0, q8_0, q3_0) and no pipeline
stages, each thread reads the words of its K and V block pairs into registers at the start of a KV tile, and
dequantizes each tile into shared memory at the place where the old loader did. The V loads are then in flight during
the K·Q and softmax steps. The arithmetic does not change. Evidence (`../prefill-kq-20261026`, RTX 4070): logits
byte-identical to the bundle engine for prompt batches (P4 E1) and for 1-32 column batches with q4_0 and q8_0 (P5c);
through the server with the 12 GB defaults (P6), cold prefill at 245k 1.057x (472.8 -> 447.1 s), 512-token turns at
128k / 245k 1.08x, decode +2.5 to +3.6 %, all reply texts identical.

On 8 GB cards the launcher converts the cache to f16 for prefill (patches 0038, 0051), so 0072 changes decode and
drafting there, not the prefill. Turing (sm_75) uses other tile sizes (64 cells per tile, 2 block pairs per thread),
so the RTX 2060 SUPER check (R7) is part of the gates.

## Gates (declared before the runs)

| Gate | Condition |
|---|---|
| R1 zip | outside `docs/` the same entries as bundle-20261025; changed: the engine `bin/` files (`ggml*.dll`, `llama*.dll`, `llama-server*.exe`, `mtmd.dll`, `test-backend-ops.exe`) and docs; the CUDA runtime DLLs and `cloudflared.exe` identical; 0 text files with control bytes; every relative link in the zip's `.md` files resolves inside the zip (the exemptions of release-20261019b); `llama-server --version` reports `a38714c63d` |
| R2 launcher | as release-20261019b R2 (default 12 GB; `BONSAI_8GB=1`; `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`; `BONSAI_TOTAL_MIB=24576`): health ok, a short greedy answer, 0 CUDA errors |
| R3 identity, RTX 4070 | release build against the bundle-20261025 engine (the `bin/` files of the zip with `llama-perplexity` of the same build): `llama-perplexity --kl-divergence-base` logit files byte-identical for q4_0, q8_0 and q3_0 K/V, (a) context 8,192, 2 chunks, `-ub 512`, (b) context 2,048, 1 chunk, `-ub 1`, `-ub 4` and `-ub 8`, batch-invariant on |
| R3b small-batch speed, RTX 4070 | release build against the 1025 engine, back to back, batch-invariant on, `llama-bench` `tg128 -r 3` at 64k and 128k and `pp4 -r 5` at 64k, for q8_0, q3_0 and q4_0 K/V: no cell below 0.97x (added 13:56 after the peer review: with head size 256 and 8 columns the prefetch holds up to 136 registers for q8_0, which can spill) |
| R4 saved conversations | as release-20261025 R4 (8 GB defaults, layer, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |
| R5 speed, 12 GB | default launcher, layer off, fresh server per depth: the bundle-20261025 zip and the candidate zip, in turns (1025, candidate) for each depth: 4k and 32k mean decode at least 0.97x of 1025, 128k cold prefill at least 1.03x of 1025; all reply texts identical to 1025 |
| R6 8 GB preset on the RTX 4070 | `BONSAI_8GB=1`, fresh server, 64k and 128k: mean decode at least 0.97x of the 1025 zip with the same settings, reply texts identical, 0 CUDA errors |
| R7 RTX 2060 SUPER (rig, P229) | (a) logit files byte-identical to bundle-20261025 for q3_0 and q4_0 K/V with `-ub 512` (context 8,192, 2 chunks) and `-ub 1 / 4 / 8` (context 2,048); (b) the 8 GB launcher (`BONSAI_8GB=1`, its own VRAM line), fresh server per depth, 64k and 128k: mean decode at least 0.97x of bundle-20261025, cold prefill at least 0.97x (prefill uses the f16 path there), reply texts identical, 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

Amendment (13:56, before any gate run): the peer review found a latent fault for wave64 HIP builds (the slot count
assumed 32 threads per warp; the host gate keeps that path off). The slot count now uses the physical warp size; for
NVIDIA the code is the same. The two commits are one commit now, `a38714c63d`. R3b is new.

## Results, RTX 4070 (14:06-15:15)

Log: [`data/release_1026.log`](data/release_1026.log). Scripts: [`gates/`](gates/). Zip sha256 `c292760a2ff0d2c4...`,
engine `a38714c63d`. Memory clock 11751 MHz in R5 and R6.

| Gate | Result | Verdict |
|---|---|---|
| R1 zip | outside `docs/`: no new or removed entries; changed: the 10 engine `bin/` files only; 0 control-byte files; 0 broken links | PASS |
| R2 launcher | default, `BONSAI_8GB=1`, `BONSAI_8GB=1 BONSAI_RS_REPLAY=0`, `BONSAI_TOTAL_MIB=24576`: health=1, a correct short answer, 0 CUDA errors each | PASS |
| R3 identity | 12 of 12 cells (q4_0, q8_0, q3_0; `-ub 512` at 8,192; `-ub 1 / 4 / 8` at 2,048): `identical` | PASS |
| R3b small batches | see the table below; lowest cell 1.005x (q8_0 pp4) | PASS |
| R4 saved conversations | 3 turns (slot files 1, 2, 3); conversations A and B take turns, turn 2 of each reads its cache (25,971 / 25,985 cells, 24-25 new tokens); 7 index entries, 4 deltas; 0 CUDA errors | PASS |
| R5 12 GB | mean decode 4k 96.6 -> 96.6 (1.000x), 32k 87.4 -> 88.3 (1.010x); 128k cold prefill 737.0 -> 767.4 tok/s (1.041x, 172.8 -> 165.9 s); 128k decode 1.033x; texts 9 / 9 identical | PASS |
| R6 8 GB preset | mean decode 64k 76.2 -> 77.9 (1.022x), 128k 60.0 -> 62.2 (1.037x); prefill 1.000x (f16 path, as expected); texts 6 / 6 identical; 0 CUDA errors | PASS |
| R7 RTX 2060 SUPER | see below (P229, issue #245) | PASS |

R3b (`llama-bench`, batch-invariant on, tok/s, 1025 -> candidate):

| K/V | tg128 at 64k | tg128 at 128k | pp4 at 64k |
|---|---|---|---|
| q8_0 | 50.58 -> 51.43 (1.017x) | 40.69 -> 42.09 (1.034x) | 139.2 -> 139.9 (1.005x) |
| q3_0 | 53.45 -> 56.57 (1.058x) | 44.52 -> 49.11 (1.103x) | 143.5 -> 147.2 (1.026x) |
| q4_0 | 53.67 -> 56.20 (1.047x) | 44.75 -> 48.54 (1.085x) | 144.3 -> 147.4 (1.021x) |

The q8_0 register risk of the review does not show: q8_0 is faster in every cell. The pp4 cells have a large spread
(about +-19 tok/s over 5 runs), so the pp4 gains are in the noise; the gate needs no cell below 0.97x, and none is.

## Results, RTX 2060 SUPER (R7, P229, 2026-10-27 10:43-11:27 CDT)

Run on the rig with `rig/r7.sh` (issue #245, where the full `r7.log` is). Stock clocks (memory 7,001 MHz, 6,801 under
load). Model: the published MTP file with its Q4_0 head, as the 8 GB launcher serves it. Engines as printed: 1025
`810d93e5aa`, 1026 `a38714c63d`.

| Gate | Result | Verdict |
|---|---|---|
| R7a identity | 8 / 8 cells `identical` (q3_0 PPL 6.6809 / 6.7478 / 6.7540 / 6.7528, q4_0 6.6383 / 6.7177 / 6.7210 / 6.7264; ub 512 at 8,192, ub 1 / 4 / 8 at 2,048) | PASS |
| R7b speed, 64k | mean decode 38.1 -> 40.1 (1.052x); cold prefill 290.1 -> 289.4 tok/s (0.998x) | PASS |
| R7b speed, 128k | mean decode 21.9 -> 22.9 (1.046x); cold prefill 227.5 -> 227.3 tok/s (0.999x) | PASS |
| R7b texts | 6 / 6 identical | PASS |
| health | 4 / 4 servers `health=1`; 0 `CUDA error` and 0 spill lines | PASS |

Record notes from the rig: the desktop held 847 MiB, so the VRAM lines were 67,072-70,144 cells instead of about 88k.
At 64k the two lines differ (1025 67,072, 1026 68,864), so that decode ratio includes ~1,800 more VRAM cells for 1026;
at 128k both lines are 70,144, and that cell (1.046x) is the clean comparison.

**All gates pass: bundle-20261026 is published as the latest release.**
