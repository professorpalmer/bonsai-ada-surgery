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

## Q01b Rebase onto the int8 page bounds (2026-10-13 21:23)

- `product-sparse` moved to `c8bbb1898` (int8 page bounds, D22). q3_0 rebased onto it: clean, `q3-on-sparse`
  `4dbfe57d4` (force-pushed). `c8bbb1898` has the same tree as patch 0055 (PR #56), so q3_0 as patch 0056 is a clean
  pick.

## Q02 Build (2026-10-13 20:49 - 22:08)

- First build on `bae6dccfe` (20:49-21:01, after the bundle-0054 gates). Rebuild on `4dbfe57d4` (21:23) stopped at
  the 21:41 power cut. The restart (21:58-22:03) failed to link: one object written during the cut was corrupt
  (`CVT1107 ... is corrupt`), and the log said rc=0 because `start /wait` hides ninja's exit code. The 124 objects
  written 21:23-21:45 were deleted and the build ran again (22:04-22:08): `LLAMA_COMMIT 4dbfe57d4f`, sm_89. The
  success check now looks at the output files.

## Q03 Op tests (2026-10-14 00:20-00:23)

- **Gate.** 0 FAIL, q3_0 cases present.
- **Result.** `FLASH_ATTN_EXT` 3115/3115 (110 q3_0 lines), `SET_ROWS` 177/177 (14), `CPY` 259/259 (7), `GET_ROWS`
  123/123 (4). 0 FAIL.
- **Verdict.** Pass.

## Q04 Perplexity (2026-10-14 00:23-00:26)

- **Gate.** q3_0 within 1 % of q4_0.
- **Setup.** wikitext-2, `-c 2048`, 32 chunks, `-fa on`, the same binary (`root-q3`), K and V the same type.
- **Result.** q8_0 8.0733 +- 0.117; q4_0 8.0900 +- 0.117; q3_0 8.1366 +- 0.118 (+0.58 % vs q4_0, +0.78 % vs q8_0).
  The 2060 measured +0.03 % vs q4_0 at 64k (P108); at 2k the cache is short, so each K/V row weighs more.
- **Verdict.** Pass.

## Q05 Sparse + q3_0 at 160k (2026-10-14 00:55-01:10)

- **Gate.** Copies 10/10, needles 12/12.
- **Setup.** `bench/sparse_prefill.sh`, `root-q3` (`4dbfe57d4`), `BONSAI_CTK=q3_0` (launcher: `window 262144 /
  q3_0`), line 32,768, sparse `8192,64,1024` with int8 bounds, graphs on, packed mask on. The first run (00:26) was
  killed by a Windows-update reboot at 00:31; this rerun ran at the stock memory clock (the OC profile was not
  applied after that reboot).
- **Result.** Copies 10/10, needles 12/12, 12 engaged lines (`bounds int8`). Mean decode 33.1 tok/s (32.5 / 30.5 /
  36.4) at the stock clock; the D22 int8 arm with q8_0 K/V gave 27.3 at the OC clock. Not an A/B (different K/V
  type and clock), but it shows the smaller host tail.
- **Verdict.** Pass.

## Q07 q3_0 on the 0055 candidate vs q4_0, sparse on (2026-10-14 13:41-15:14)

- **Gate.** In `README.md`, written 13:45 before the run.
- **Setup.** `q3-on-0055` `7c7b47e156` (= `product-0055` + q3_0, a clean pick), root-q3-55 (root-0055 + these sm_89 bins),
  line pinned at 32,768, sparse `12288,64,1024` (the 0055 opt-in rule), graphs on, packed mask on,
  `bench/q3_q07.sh` (`bench/sparse_prefill_n.sh`), memory clock 11751 MHz under load, driver 610.88.
- **Result.**

  | depth | items | K/V | copies | needles | mean decode |
  | ---: | --- | --- | ---: | ---: | ---: |
  | 200k | 20 | q4_0 | 20/20 | 12/12 | 30.7 |
  | 200k | 20 | q3_0 | 20/20 | 12/12 | **31.8** (+3.6 %) |
  | 245k | 10 | q4_0 | 10/10 | 12/12 | 26.7 |
  | 245k | 10 | q3_0 | 10/10 | 12/12 | **28.1** (+5.2 %) |

- **Verdict.** Pass. q3_0 equals q4_0 on every item with sparse on, and decodes faster at the same pinned line (fewer
  bytes per host row). On an 8 GB card the larger win is the line itself (1.31x more positions in VRAM, P114); the 2060's
  P129-P132 measure that on this build.

## D27 Faster q3_0 tile dequant (q3-fast) (2026-10-14 15:30-15:44)

- **Question.** The 2060 measured q3_0 6.5 % slower than q4_0 at 64k (P114, the dequant cost). Does a faster MMA tile
  dequant (packed half2: each pair of 3-bit codes becomes `1024 + q` in one half2, bit-exact with the float path) close
  it before the 0056 default decision?
- **Gate.** In the script header (the kernel session's `d27_q3fast.sh`), before the run: FLASH_ATTN_EXT 0 FAIL on
  q3-fast; q3-fast answers byte-identical to q3-old (3 prompts, temp 0); q3-fast 64k decode not below q3-old. Reported:
  q3-fast vs q4_0.
- **Setup.** q3-fast = fork `df218650a` (`7c7b47e156` + the dequant), root `root-q3fast`; q3-old = `root-q3-55`. 12 GB
  recipe with `BONSAI_CTK` forced, 64k all in VRAM, graphs on, `bench/quick_tps.py`, alternated x2, 11751 MHz under
  load, driver 610.88. The build (idle priority) ended before the run.
- **Result.** Op tests 3115/3115, 0 FAIL. Answer hashes: q3-old `a090a7f00152d5ef` = q3-fast `a090a7f00152d5ef`.

  | arm | r1 | r2 | mean | vs q4_0 |
  | --- | ---: | ---: | ---: | ---: |
  | q4_0 | 79.6 | 78.9 | 79.25 | - |
  | q3_0 old | 76.6 | 76.3 | 76.45 | -3.5 % |
  | q3-fast | 77.9 | 78.1 | **78.0** | **-1.6 %** |

- **Verdict.** Pass. q3-fast is bit-exact and halves the shallow cost of q3_0 on the 4070 (+2.0 % over q3-old). For the
  0056 rule: the 2060's quality items on `7c7b47e156` stay valid (bit-exact), and rule item 1 (64k within 5 % of q4_0)
  moves to the q3-fast build.

## D28 Packed-half dequant for q4_0 and q8_0 (2026-10-14 15:49-16:07)

- **Question.** The packed-half tile dequant (D27) extended to q4_0 (the 8 GB default) and q8_0 (the 12 GB default): is it
  bit-exact, and not slower?
- **Gate.** In the script header (the kernel session's `d28_q48fast.sh`), before the run: FLASH_ATTN_EXT 0 FAIL;
  q4-old = q4-new and q8-old = q8-new answer hashes; new decode at 64k not below old, per type.
- **Setup.** new = fork `q3-fast` `be604dec0` (`df218650a` + q4_0 / q8_0), root `root-q3fast2`; old = `root-q3-55`
  (`7c7b47e156`). 64k all in VRAM, 12 GB recipe with `BONSAI_CTK` forced, alternated x2, driver 610.88. The build
  ended before the run.
- **Result.** Op tests 3115/3115, 0 FAIL. Hashes: q4_0 old = new = `edf0b1fbd89000ba`; q8_0 old = new =
  `6e056aae95e76a19`. Mean decode at 64k (r1 / r2): q4_0 old 79.4 / 79.3, new 79.7 / 80.0 (+0.6 %); q8_0 old 78.4 /
  78.5, new 78.9 / 79.2 (+0.8 %).
- **Verdict.** Pass. Patch 0057 = the packed-half dequant for q3_0, q4_0 and q8_0 (bit-exact, slightly faster);
  release gates in `../release-20261014b/`.

## Q06 2060 set

- **Status.** Asked on #21 (2026-10-14 01:15): P108 / P114 / P117 on `4dbfe57d4` for `75-real`.

## Open: launcher

- The launcher's `CellBytes` switch has no q3_0 entry (it falls back to the q8_0 size, so the VRAM line is too low,
  not unsafe). The entry is 14,336 B per cell (16 layers x K+V x 4 heads x 256 dims x 3.5 bits / 8). It goes in after
  the sparse launcher PR (#49) merges, on the same line.
