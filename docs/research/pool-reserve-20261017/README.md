# Default pool reserve on the 8 GB preset (2026-10-17)

Plans and gates: #138 (PR1 comment 6234775266, PR2 comment 6235261102), declared before the runs. Hypothesis by the
kernel session; the launcher default is this branch.

## PR1: the cause of the full-card prefill slowdown (4070, bundle-20261017b zip, 8 GB preset, line 80,640, layer off)

| arm | cold 16k prefill | decode | pool |
| --- | --- | --- | --- |
| P0 no ballast | 1,247.8 tok/s | 85.2 | 35 steps of 2 MiB, to 70 MiB |
| PA ballast after `/health` (53 MiB free) | 395.1 tok/s (3.2x slower) | 85.2 | the same steps, each on a full card |
| PB `GGML_CUDA_POOL_RESERVE_MIB=256`, then the ballast | 1,218.6 tok/s (-2.3 %) | 85.1 | one growth of 256 MiB at the first use |

0 CUDA errors, 0 failed growths. CONFIRMED: the pool's 2 MiB growth steps on a full card wait on Windows; decode needs
no growth.

## PR2-a: the peak

A cold 245k read on the same recipe: pool[0] only, 79 steps, **170.0 MiB**: the same as a cold 131k read
(pool_peak_0060p, kernel session); 16k: 70 MiB; the 2060's growth after a restore: 142 MiB (P158d). Prefill 526.1
tok/s, 0 CUDA errors. Receipts in the serve folder: `docs/receipts/pr1_pool.log`, `pr2a_peak.log`.

## PR2-b: the default

The 8 GB preset sets `GGML_CUDA_POOL_RESERVE_MIB=176` (the peak rounded up to 16) when the shared pool is on, MTP is on,
the engine has the knob, and the user did not set it. 6 MiB over the peak, so the VRAM line does not change. Gates
G1-G3 as declared in PR2; results below.

## PR2-b results: G1 + G3 (4070, the branch launcher 7859cc9 on the bundle-20261017b zip bins; `pr2b_gates.log`)

| check | result |
| --- | --- |
| G1 cold 128k, 8 GB preset, reserve on / off / on / off | 757.6 / 756.6 / 756.3 / 756.6 tok/s prefill (within 0.2 %), decode 45.2-45.8; with the reserve the pool grew once (176 MiB) and never again; without it 79 steps |
| G1 squeeze (card full after `/health`, cold 16k), reserve on | **1,217.5 tok/s** (P0 1,247.8: -2.4 %; without the reserve 395.1); the spill line printed |
| G3 12 GB default, 24 GB path | no reserve set (no 176 MiB growth) |

0 CUDA errors in all runs. G1 and G3 PASS. G2 (the 2060) asked on #138.
