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
| R3b small-batch speed, RTX 4070 | release build against the 1025 engine, back to back, batch-invariant on, `llama-bench` `tg128 -r 3` at 64k and 128k and `pp4 -r 5` at 64k, for q8_0, q3_0 and q4_0 K/V: no cell below 0.97x (added 15:05 after the peer review: with head size 256 and 8 columns the prefetch holds up to 136 registers for q8_0, which can spill) |
| R4 saved conversations | as release-20261025 R4 (8 GB defaults, layer, slot folder, 3 turns, then two conversations that take turns); 0 CUDA errors |
| R5 speed, 12 GB | default launcher, layer off, fresh server per depth: the bundle-20261025 zip and the candidate zip, in turns (1025, candidate) for each depth: 4k and 32k mean decode at least 0.97x of 1025, 128k cold prefill at least 1.03x of 1025; all reply texts identical to 1025 |
| R6 8 GB preset on the RTX 4070 | `BONSAI_8GB=1`, fresh server, 64k and 128k: mean decode at least 0.97x of the 1025 zip with the same settings, reply texts identical, 0 CUDA errors |
| R7 RTX 2060 SUPER (rig, P229) | (a) logit files byte-identical to bundle-20261025 for q3_0 and q4_0 K/V with `-ub 512` (context 8,192, 2 chunks) and `-ub 1 / 4 / 8` (context 2,048); (b) the 8 GB launcher (`BONSAI_8GB=1`, its own VRAM line), fresh server per depth, 64k and 128k: mean decode at least 0.97x of bundle-20261025, cold prefill at least 0.97x (prefill uses the f16 path there), reply texts identical, 0 CUDA errors |

All pass: publish as the latest release. Any fail: no publish; log why.

Amendment (15:05, before any gate run): the peer review found a latent fault for wave64 HIP builds (the slot count
assumed 32 threads per warp; the host gate keeps that path off). The slot count now uses the physical warp size; for
NVIDIA the code is the same. The two commits are one commit now, `a38714c63d`. R3b is new.
