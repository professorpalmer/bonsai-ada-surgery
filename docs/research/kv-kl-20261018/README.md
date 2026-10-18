# K/V cache types against an f16 K/V cache: KL divergence (2026-10-18)

The question (a user): how much does the q3_0 K/V cache (the 8 GB default) drift? Measured with `llama-perplexity
--kl-divergence` on the product bins (engine 96f6e49cdc), model `Ternary-Bonsai-2-27B-PTQ1_0.gguf`, wikitext-2 test,
flash attention on, RTX 4070, a plain context (no tier). Each type against an f16 K/V base made with the same bins.
Script `kl_q3.sh`, logs `kl_<type>_<ctx>.log`, summary `kl_q3.log`.

| K/V cache | mean KL | median KL | 99 % KL | top token = f16 | PPL vs f16 |
| --- | --- | --- | --- | --- | --- |
| q8_0, 16k x 4 chunks | 0.000235 | 0.000087 | 0.0011 | 99.33 % | -0.03 % |
| q4_0, 16k | 0.002115 | 0.001033 | 0.0148 | 97.90 % | +0.25 % |
| **q3_0, 16k** | **0.008022** | **0.004019** | **0.0583** | **95.97 %** | **+0.45 %** |
| q8_0, 32k x 2 chunks | 0.000207 | 0.000101 | 0.0013 | 99.27 % | -0.09 % |
| q4_0, 32k | 0.002260 | 0.001105 | 0.0144 | 97.68 % | +0.37 % |
| **q3_0, 32k** | **0.009066** | **0.004366** | **0.0615** | **95.63 %** | **-0.05 % (noise)** |

Reading: q3_0's per-token drift is about 4x q4_0's and about 40x q8_0's (mean KL ~0.008-0.009, the top token the same as
f16 ~96 % of the time). Perplexity barely moves (+0.45 % at 16k, within noise at 32k), and no task loss has been measured
(HumanEval 160/164 with q3_0 on 8 GB, P117; copies and needles at 160k-245k equal to q4_0, P114 / P130). q3_0 is the
8 GB default because it fits ~22 % more positions in VRAM than q4_0; `BONSAI_CTK=q4_0` or `q8_0` gives less drift where
the positions fit.
