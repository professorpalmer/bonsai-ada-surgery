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
