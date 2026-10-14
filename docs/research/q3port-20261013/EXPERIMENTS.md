# Experiments Q01-Q06

Format per entry: **question**, **gate**, **setup**, **result**, **verdict**, **receipts**. Times are local (CDT).

---

## Q01 Rebase onto the current engine (2026-10-13 20:10-20:20)

- **Question.** Does the q3_0 commit (46 files, +591 / -14) apply to `product-0054` and to `product-sparse`?
- **Result.** Clean cherry-pick onto both (no conflicts). The sparse first fill calls
  `ggml_get_to_fp16_nc_cuda(K->type)`; the q3_0 commit already has the `Q3_0` case there (and in `to_fp16`,
  `to_fp32`, `to_bf16`). The sparse path has no K-type gate (only `mask->type == F16`). The commit message now gives
  the block layout (f16 d, 8 bytes of 2-bit low parts, 4 bytes of 1-bit high parts, x = d * (q - 4)) and the 2060
  results; it said "WIP, not built or tested", which was out of date.
- **Verdict.** Done: fork `q3-on-sparse` `bae6dccfe`.

## Q02 Build

- **Setup.** `build-q3`, sm_89, targets llama-server, llama-perplexity, test-backend-ops; starts after the bundle-0054
  gates (no CPU load during their speed arms), low priority.
- **Status.** Queued.

## Q03-Q05 4070 checks

- **Gates.** See `README.md`.
- **Status.** Queued after D21 (the sparse product check), before the other GPU work.

## Q06 2060 set

- **Status.** Asked on #21 after Q03-Q05 pass.

## Open: launcher

- The launcher's `CellBytes` switch has no q3_0 entry (it falls back to the q8_0 size, so the VRAM line is too low,
  not unsafe). The entry is 14,336 B per cell (16 layers x K+V x 4 heads x 256 dims x 3.5 bits / 8). It goes in after
  the sparse launcher PR (#49) merges, on the same line.
