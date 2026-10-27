# fp16 accumulation in the prefill K·Q step, on top of bundle-20261026 (prefill-fp16acc-20261027)

Plan written before the runs (2026-10-27, 12:15).

## Why again

The main complaint about this serve is the cold read of a long prompt: 245k tokens take 1,489 s on the RTX 2060 SUPER
and 447 s on the RTX 4070 (bundle-20261026 engine). About 60-80 % of that time is attention over the earlier tokens.

P2 of `prefill-kq-20261026` let the K·Q product of the wide prefill tiles accumulate in fp16 instead of fp32 (the V·KQ
step and the softmax stay fp32). On the 4070 it gave 1.116-1.121x at 245k. It was not kept, because its logits move
(mean KLD 0.000925, same top 98.62 %), and that looked like lost precision. `fa-config-20261026` then showed that a
change of only the tile size moves the logits by the same amount (0.00086, 98.66 %). So P2 is not shown to lose
precision, and the KL limit was the wrong gate for it. This study gates it on answers instead.

On GeForce Turing, tensor-core math with fp32 accumulation runs at half the fp16-accumulation rate (as on GeForce
Ada), so the 2060 can gain more than the 4070. That needs the rig (P231, after P230).

Engine: `research/pkq-fp16acc-1026` (`e5c4e35fc1`) = `a38714c63d` (bundle-20261026) + the P2 commit, built with
`-DGGML_PKQ_FP16ACC`, `75-real;89-real`. Test root: the bundle-20261026 candidate root with only `ggml-cuda.dll` from
that build (the change is in that file only). Control: the bundle-20261026 candidate root.

## Runs and gates (declared before the runs)

| Run | What | Gate |
|---|---|---|
| F0 | `test-backend-ops -o FLASH_ATTN_EXT` (P2 build) | record the result; a failure on a tolerance is information, not a stop, because F2 is the quality gate |
| F1 | `llama-perplexity` q4_0, context 8,192, 2 chunks, `-ub 512`, `--kl-divergence` against the 1026 engine | record (expected near 0.0009) |
| F2 | RTX 4070, 12 GB launcher defaults (layer off), a fresh server per set: the P170 code set and prose set (24 items each over a ~245k-token document, greedy, thinking off; the T5 driver), control root then P2 root | at most 1 confident wrong answer (a wrong answer that does not say "not stated" or similar) where the control is right, both sets together; total right at least the control's minus 1; 0 CUDA errors |
| F3 | the first item of each F2 set is a cold read of the document: its wall time, P2 root against control | at least 1.05x on each set |
| F4 | `bench/quick_tps.py`, fresh server per depth, 64k and 128k, control then P2: cold prefill and decode, texts saved | cold prefill at 128k at least 1.03x; decode at least 0.98x; texts: record how many differ (P2 changes the arithmetic, so differences are expected and are not a gate) |

All pass: P2 becomes a candidate for the next bundle (12 GB), behind its own release gates (a switch with default on, a
HumanEval run). Then P231 on the rig for the 8 GB preset. Any fail: not kept; log why.

## Results, RTX 4070 (12:16-13:04)

Log and data: `data/` (`p2b.log`, the F2 answers, F4 texts). Control root: bundle-20261026 (`a38714c63d`). P2 root: the
same, with `ggml-cuda.dll` of `e5c4e35fc1`. 12 GB launcher defaults, layer off, VRAM line 223,744 cells, memory 11,751 MHz.

| Run | Result | Verdict |
|---|---|---|
| F0 | FLASH_ATTN_EXT 3115 / 3115 | pass |
| F1 | mean KLD 0.000925, max 0.174, same top 98.62 %; PPL 6.6422 against 6.6370 (+0.08 %) | recorded |
| F2 | code set 21 / 24 against 21 / 24 (no answer changed); prose set 11 / 24 against 11 / 24 (7 answer texts changed: lost item 1, "kerosene" -> "diesel", a confident wrong answer; gained item 9; 5 changes in wording only). Confident wrong answers where the control is right: 1 (limit 1); total right 32 = 32; 0 CUDA errors | **PASS** (at the limit) |
| F3 | cold read of the document: code 438.1 -> 420.8 s (1.041x), prose 442.5 -> 422.6 s (1.047x) | **FAIL** (at least 1.05x each) |
| F4 | cold prefill 64k 987.4 -> 1017.5 tok/s (1.030x), 128k 767.7 -> 796.6 (1.038x); decode 64k 81.6 -> 82.6 (1.012x), 128k 75.4 -> 75.0 (0.995x); 512-token turns at 128k 1.04-1.05x; texts 0 / 6 identical (expected); 0 CUDA errors | pass |

**Verdict for 12 GB: not kept** (F3 fails). On the 4070 the cold read of a ~240k-token document gains only 4-5 %:
P1's 1.12x is the gain of one 512-token batch at 245k, and a cold read averages over all depths from 0 to 240k and
includes the work that is not attention. 4 % does not pay for an arithmetic change that moves one answer in 48.

## P231: the same change on the RTX 2060 SUPER (declared 13:10, after the 4070 verdict)

The reason for a separate run: on GeForce Turing the tensor-core math with fp32 accumulation runs at half the rate of
fp16 accumulation, and P230 showed that the 2060's prefill at depth is not limited by loads. So the 2060 can gain
much more than the 4070, and the 8 GB cards are where the cold read hurts (245k: 1,489 s). F2's answers show that the
change is safe at the T5 standard on the 4070. The 2060 runs other kernels (64-cell tiles, the f16 copy), so its own
answers are checked in stage 2.

| Stage | What (RTX 2060 SUPER, stock clocks, the 8 GB launcher's model file) | Gate |
|---|---|---|
| 1 | `llama-bench` q3_0, `-ub 512`, batch-invariant on, the 8 GB copy settings (`GGML_CUDA_FA_PREFILL_F16=32768`, `GGML_CUDA_FA_CHUNK=32768`): pp512 at 8k, 32k and 64k, the 1026 engine and P2 in turns, 2 rounds; `llama-perplexity` KL of P2 against 1026 (q3_0, ctx 8,192, the copy settings) | go to stage 2 if P2 is at least 1.08x at 32k and at 64k in both rounds; else stop, P2 is not kept for 8 GB |
| 2 | (a new issue) the 8 GB launcher, the 1026 root against the P2 root: cold reads at 64k and 128k, and the P170 code and prose sets with the F2 rule | cold read at 128k at least 1.08x; F2 rule (at most 1 confident wrong answer where 1026 is right, total right at least 1026's minus 1); decode at least 0.98x |

Stage 2 passes: P2 becomes an 8 GB-only switch (on in the 8 GB preset) for the next bundle, with its own release gates.

## P231 stage 1 results (RTX 2060 SUPER, 2026-10-27 12:07-12:33 CDT, issue #250)

Stock clocks (memory 7,001 MHz), the published MTP file with its Q4_0 head, q3_0, the 8 GB copy settings; 0 `CUDA
error` lines. The full log and jsonl rows are on #250.

| Cell | 8k | 32k | 64k |
|---|---|---|---|
| r1 1026 | 395.61 | 305.55 | 233.76 |
| r1 P2 | 386.13 | 303.33 | 238.93 |
| r2 1026 | 380.26 | 296.34 | 230.81 |
| r2 P2 | 382.46 | 301.30 | 237.91 |
| P2 / 1026, r1 / r2 | 0.976 / 1.006 | 0.993 / 1.017 | 1.022 / 1.031 |

KL of P2 against 1026 (q3_0, copy settings, ctx 8,192): mean KLD 0.002502, max 0.605, same top 97.61 %, PPL 6.6613
against 6.6809.

**Verdict: FAIL** (at least 1.08x at 32k and at 64k in both rounds). Stage 2 does not run. **P2 is closed for both
cards.** On the 2060 the fp16 accumulation gives at most 2-3 % at 64k: the K·Q accumulation rate is not the main cost
of prefill at depth there either. With P230 (loads are not the limit either), two guesses about the 2060's prefill
cost failed. The next step measures where the time goes before any new change: the engine's per-op GPU timer
(`GGML_CUDA_OP_TIMING=1`) over a depth fill.
