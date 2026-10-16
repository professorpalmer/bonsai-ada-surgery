# Drafter A/B, 2026-10-14 13:17-13:29: small models as draft models for the 27B

Product engine (bundle-20261013, 0054), 12 GB recipe, memory OC on (11751 MHz under load), driver 610.88, one server
per arm, bench/quick_tps.py at two depths (mean decode, code / prose / bash, greedy, lookup on as shipped).

| arm | mean decode (depth 1 / depth 2) |
| --- | --- |
| MTP draft 2 (shipped) | **94.1 / 101.8** |
| MTP draft 1 | 86.8 / 95.9 |
| MTP draft 3 | 87.9 / 99.9 |
| MTP draft 4 | 68.6 / 79.5 |
| MTP draft 8, p-min 0.85 | 33.7 / 38.5 |
| standalone draft model 2B (draft-simple, draft 6) | 21.2 / 25.9 |
| standalone draft model 4B | crashed at start: GGML_ASSERT(ptr == pool_addr + pool_used), ggml-cuda.cu:682 |

Verdict: the shipped MTP draft 2 stays. Standalone small-model drafters lose 4x; no case for them on this card.
The 4B arm hit a shared-CUDA-pool ordering assert with a second (draft) model context: a generic engine bug for
-md draft models with the shared pool on.
Earlier partial runs (stopped for other GPU jobs) are void.
