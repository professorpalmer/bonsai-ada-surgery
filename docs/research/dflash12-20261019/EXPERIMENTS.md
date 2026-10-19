# Experiments

One entry per run. Decode is tok/s, `bench/quick_tps.py` (mean of code / prose / bash, 400-token greedy answers), a
fresh server for each depth. Receipts: `receipts/depth_table_dflash12-*.log`, `receipts/dflash.log`, `receipts/run.sh`.

## DF1: DFlash 2 drafter (naklitechie r3 Q4_K_M) against the 12 GB default

- When: 2026-10-19 14:16-14:52, 0.6 GPU-h. RTX 4070, display on the iGPU, bundle-20261019a root.
- D0 probe at 4k: lowest free VRAM 374 MiB for C (margin 1000), 572 MiB for D (margin 2400) -> drafter cost
  1,202 MiB -> D margin 2,202 MiB -> VRAM line 185,088 positions (C: 260,352).
- D1 (D = `ngram-mod,draft-dflash`, the drafter on the GPU) against C (the fresh-server table of the same morning):

| depth | C decode | D decode | change | C cold prefill | D cold prefill | change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4k | 96.5 | 84.2 | -12.7 % | 1,297 | 1,197 | -7.7 % |
| 32k | 86.8 | 79.1 | -8.9 % | 1,151 | 1,103 | -4.2 % |
| 64k | 79.2 | 73.3 | -7.4 % | 968 | 937 | -3.2 % |
| 128k | 72.0 | 65.8 | -8.6 % | 739 | 720 | -2.5 % |
| 192k | 61.8 | 46.1 | -25.4 % | 597 | 585 | -2.0 % |
| 245k | 60.4 | 40.7 | -32.6 % | 516 | 507 | -1.8 % |
| mean | 76.1 | 64.9 | -14.8 % | | | |

- Control check: C at 4k 96.6 (morning 96.5) and at 128k 72.3 (72.0), both within 2 %: the morning table holds.
- The drafter was active: `draft-dflash` in every D server log, acceptance 0.53-0.82 per request.
- G1 FAIL (mean -14.8 %, +5 % required). G2 FAIL (every depth below C; 245k -32.6 %). G3 pass (128k prefill -2.5 %).
  G4 FAIL: 0 CUDA errors, but the launcher's spill guard reports +722 MiB in every D run (also in the probe with
  572 MiB free; 0 in every C run).
- The +722 MiB is the same at margin 2,202 and 2,400 while VRAM is still free, so it is a fixed host-side allocation
  of the drafter, not cache pressure. Not taken further: with it in VRAM the drafter would cost about 1.9 GB, the line
  would fall by about 40k more positions, and the deep depths would lose more. The -8 to -13 % at shallow depth can
  come partly from that host-side part.
- Verdict: **rejected for 12 GB.** The MTP head that comes in the model file is faster at every depth and costs no
  extra VRAM. This agrees with P033 on 8 GB.
