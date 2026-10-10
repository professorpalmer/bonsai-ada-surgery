# Decode efficiency on the RTX 4070 (2026-10-09)

Question: below the VRAM line, how close is one decode step to the time the card needs to read the weights once?

## Method

- **Bytes per step:** every weight tensor except the token embedding (one row per token, kept in system RAM) and the
  MTP block (not run when drafting is off): 5.657 GB for `Ternary-Bonsai-2-27B-PTQ1_0` (5,340 MiB of it PTQ1_0).
- **Peak:** 11,751 MHz memory clock on this card (overclocked) x 192-bit GDDR6X = ~564 GB/s (504 GB/s at stock).
- **Speed:** `llama-bench` tg128 with drafting off; `bench/decode_bw.sh` for the serve with drafting and the layer off.
- **Kernel timeline:** `tools/decode-trace/` (CUPTI activity records, CUDA graphs on, as in the serve). CUPTI activity
  tracing needs no GPU performance-counter permission. `decode_trace.exe <model> <out.csv> 64 64 8192 <cupti dll> [3]`,
  then `python tools/decode-trace/summarize.py <out.csv> 5.657`.

## Results

| Step | Wall | GPU busy | Kernels | Weight reads |
|---|---:|---:|---:|---:|
| 1 token (drafting off) | 14.6 ms (68.3 tok/s, llama-bench) | 13.9 ms | 1,526 | 407 GB/s over busy time |
| 3 tokens (shape of a draft-2 verification step) | 17.9 ms | 16.3 ms | 1,606 | 346 GB/s |

1 token, by kernel:
- PTQ1_0 mat-vec: 11.06 ms, 79 % of the step, ~506 GB/s = **~90 % of peak**. Little is left here.
- The other ~1,300 kernels: ~2.8 ms. Each takes 1-8 us (Hadamard + Q8 quantize 0.50 ms, gated delta net 0.39 ms,
  RMS norms 0.53 ms, BF16 gate projections 0.26 ms, attention 0.22 ms, copies 0.17 ms ...). No single large item.
- Idle time inside a step: 0.27 ms. Host time between steps (sampling, graph launch): ~1.2 ms in this tool.

3 tokens: the PTQ1_0 3-column kernel takes 12.1 ms (74 %). One avoidable item was the gated-delta-net conv-state
concat: 48 calls of 14 us in the generic non-contiguous kernel (0.68 ms per step). The engine already had a
transpose kernel for this exact layout, enabled only on GB10. Patch 0050 enables it on every NVIDIA card:
`bench/concat_ab.sh`, `receipts/concat_ab.log`: decode +1.4 % (91.8 vs 90.0 / 91.0 tok/s at depth 0, 97.4 vs
96.1 / 95.8 at 16k), the same text in 6/6 greedy answers.

## Prefill, for comparison

One 512-token micro-batch (the 12 GB recipe's `-ub 512`) at depth 1-3k: 389 ms of GPU time (~1,316 tok/s).

- PTQ1_0 matmul (`mul_mat_q`, int8 tensor cores on Q8_1 activations): 251 ms, **64.5 %**. 27.5 TOPs of work per
  micro-batch in 251 ms is ~110 TOPS, about half of the card's dense int8 tensor peak. The per-128 group scales of
  PTQ1_0 keep this in the MMQ kernel (one large int8 GEMM would need one scale per row).
- Gated delta net: 52 ms, **13.4 %** (1.09 ms per layer). It walks the tokens of the micro-batch one after another, so
  it is latency-bound; a chunked (parallel-in-time) form of the delta rule is the known way to make it faster.
- Attention 4.1 %, SwiGLU 3.8 %, Hadamard 3.1 %, activation quantize 2.4 %, norms 3.3 %.

## Conclusion

At short context the 1-token step is within ~15 % of the time to read the weights once at the card's peak. The
mat-vec kernel is near peak. The rest is spread over many small kernels, so further gains need fusion work for a few
percent each. Past the VRAM line the PCIe link sets the speed (23.7 of 23.8 GB/s measured), so this work does not
change decode at depth.
