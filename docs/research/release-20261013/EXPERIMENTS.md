# Experiments G01-G08 (and G02b)

Format per entry: **question**, **gate** (and where it was declared), **setup**, **result**, **verdict**,
**receipts**. RTX 4070 12 GB, 12 GB recipe, unless stated. Times are local (CDT).

---

## G01 Perplexity, MMA vs recurrent (2026-10-13 16:31-16:33)

- **Question.** D14 gave HumanEval 158/164 against 160/164, with both flips on long-thinking items. Does the MMA
  kernel change the model's token-level output?
- **Gate.** Declared in chat before the run; the exact limit was not written down. The result is far inside the
  error bar (+-0.117), so any reasonable limit passes.
- **Setup.** `bench/gdn_ppl_ab.sh`, root `/tmp/root-gdn2` (the `e63ce36d9` build), `-c 2048`, 32 chunks, the same
  binary for both arms (`GGML_CUDA_GDN_MMA_DISABLE=1` for the recurrent arm).
- **Result.** Recurrent 8.0714 +- 0.117; MMA 8.0733 +- 0.117 (+0.024 %). Per-chunk values differ in the third or
  fourth digit; the "engaged" line shows 1 time in the MMA arm and 0 times in the recurrent arm.
- **Verdict.** Pass. The HumanEval flips are trajectory noise on long-thinking items, not a quality loss.
- **Decision.** The HumanEval gate for the bundle becomes "at least 157/164" (G06), not the same text: the kernel
  changes the float order, so the same-text gate of 0053 cannot hold.
- **Receipts.** `docs/receipts/gdn_ppl_ab.log`.

## G02 RTX 2060 SUPER (sm_75) check (2026-10-13, P116, by the 8 GB tester)

- **Question.** Does 0054 change anything on a card without the BF16 MMA path?
- **Gate.** Declared on PR #40: the 8 GB launcher at 32k, 0053 vs 0054, no loss in prefill or decode.
- **Setup.** `product-0054` `e63ce36d9` for `75-real`, 8 GB 262k launcher (test copy with `BONSAI_BIN`, layer off),
  VRAM line 62,464, the arms run alternately two times, one server per arm, `bench/quick_tps.py` at 32k.
- **Result.** Pass on all three gates (see PR #40). The tester's code note: on sm_75 the branch allocated its
  temporaries and activated the gates before the launch found no BF16 MMA, so the log said "not taken" and not
  "skipped". The cost was not measurable.
- **Verdict.** Pass. The note was applied as G03.
- **Receipts.** PR #40 comments.

## G02b RTX 2060 SUPER (sm_75) on the merged commit (2026-10-13, P116b, by the 8 GB tester)

- **Question.** Does the merged 0054 (`de873117e`, device check first) still pass on Turing, and is the skip clean?
- **Gate.** The G02 gate (no loss at 32k), plus the "skipped: device cc" line and no "not taken" line.
- **Setup.** `75-real` build of `de873117e`, 8 GB 262k launcher (test copy, layer off), VRAM line 62,464, one server
  per arm, 32k.
- **Result.**
  - `GATED_DELTA_NET` 55/55.
  - Server log, once: `chunked GDN prefill (MMA) skipped: device cc 750 has no supported BF16 MMA schedule;
    recurrent kernel`; 0 "not taken", 0 "engaged".
  - 0053 vs `de873117e`: code prefill 347.3 vs 344.9 tok/s (32,044 tokens), follow-ups 264.7 / 263.2 vs 263.1 /
    263.2, mean decode 45.1 vs 44.8 (within 0.7 %; G02 on `e63ce36d9` gave 343.9 / 344.0 and 44.9 / 44.7). 0 one-token
    answers.
- **Verdict.** Pass. The skip is clean on Turing.
- **Receipts.** PR #40 comments (P116b).

## G03 Device check before the temporaries, 4070 op test (2026-10-13 17:44)

- **Question.** After the change from G02 (the device is checked before any GDN MMA temporaries), does the kernel
  still engage on the 4070 and do the op tests still pass?
- **Gate.** Declared by the patch owner before the run: `GATED_DELTA_NET` 0 FAIL, the same pass count as before, and
  the "chunked GDN prefill (MMA) engaged" line on the 4070.
- **Setup.** `build-gdn` (sm_89) and `build-gdn-75` (sm_75) both built clean. On the 4070:
  `test-backend-ops -o GATED_DELTA_NET -b CUDA0` from `build-gdn\bin`, with the repo `bin/` first on `PATH`.
- **Result.** 55/55 passed, 0 FAIL, 2/2 backends. The "chunked GDN" line shows on 2 lines (one engaged case and one
  "skipped: 64 tokens" case, below the size limit). Cases outside the kernel show "not supported [CUDA0]".
- **Count note.** D14 wrote "57 / 0". That number was `grep -c OK` = 55 cases + 2 backend lines; 55 is the case
  count.
- **Verdict.** Pass. Patch 0054 is now `de873117e` (PR #40, merged 17:46, main `a698946eb`).
- **Receipts.** `docs/receipts/p54b_optest_4070.log`.

## G04 Release build (2026-10-13 17:47-17:48)

- **Question.** Build the release bins from the merged patch.
- **Gate.** None (build). Checks: `LLAMA_COMMIT` = the release commit, the CUDA archs of the release, and the new
  log text in `ggml-cuda.dll`.
- **Setup.** Source `%TEMP%\stock-adfffbe` checked out at `de873117e1` (tree `165e10e3`, the same tree as the patch
  stack); build dir `tooling/build-release-20261007`, incremental, `-j 6`.
- **Result.**
  - First build: exit 0, but `LLAMA_COMMIT` stayed `e63ce36d96`. `common/build-info.cpp` is written at configure
    time, so a plain incremental build after a checkout keeps the old commit string.
  - A cmake configure and then the build: `LLAMA_COMMIT = "de873117e1"`, archs `75-real;86-real;89-real;89-virtual`,
    the "skipped: device cc" text is in `ggml-cuda.dll`.
  - The 10 runtime files were copied into `/tmp/root-0054/bin` (byte compare OK); the `e63ce36d9` bins there are gone.
- **Verdict.** Done. Lesson: after any checkout in the source tree, configure before the release build, and check
  the embedded commit (`grep -a` on `llama-common.dll`).
- **Receipts.** `logs/build_0054b.log`, `logs/build_0054b2.log` (local); note in `docs/receipts/release_0054.log`.

## G05 Gate: op tests on the release bins (2026-10-13 19:39-19:40)

- **Gate.** See `README.md` (written before the run).
- **Result.** `FLASH_ATTN_EXT` 3007 OK, 0 FAIL; `GATED_DELTA_NET` "ok 57" in the queue's count, which is 55 cases + 2
  backend lines (G03), 0 FAIL.
- **Verdict.** Pass.
- **Receipts.** `docs/receipts/release_0054.log`.

## G06 Gate: HumanEval 164 on the release bins (2026-10-13 19:41-20:40, re-scored 20:55)

- **Gate.** See `README.md`: at least 157/164.
- **Result, first scoring: 35/164, VOID.** 128 of the 164 test runs ended with exit code 3221225794 (0xC0000142,
  STATUS_DLL_INIT_FAILED): the test process did not start. The failures begin at task index 36, at about 19:51, the
  minute the Claude session that owned the queue ended and a new one started. The queue kept running, but child
  processes that need a console failed after that. The model output was not affected: all 164 answers are identical
  to the D14 run on the same kernel (`artifacts/humaneval-gdnmma`), and the token counts match (mean 2313, median
  576, 19 over 4k).
- **Re-score.** `bench/humaneval_run.py --rescore` on the saved answers, from the new session: **158/164**, the same
  6 fails as D14 (HumanEval/10, 47, 83, 116, 132, 145).
- **Verdict.** Pass (158 >= 157).
- **Lesson.** After a session restart, a queue that is still running can lose its console. Check the result
  fields of any run that spans the restart, and start later jobs from the new session. (The job that this queue
  would have started next was stopped and is restarted from the new session.)
- **Receipts.** `docs/receipts/he_template_ab.log` (b0054), `artifacts/humaneval-b0054/rescore.json` (local).

## G07 Gate: prefill and decode at 4k / 32k / 128k (2026-10-13 20:40-20:49)

- **Gate.** See `README.md`: prefill not slower at any depth, mean decode within 2 % of 0053.
- **Setup.** `bench/depth_arms.sh bench/arms/release_0054.txt` (tag rel0054): the product `bin/` (0053) vs
  `/tmp/root-0054` (0054), launcher defaults, one server per arm. A CPU build of another branch ran 19:54-20:04,
  before these arms: no overlap.
- **Result.**

  | depth | prefill 0053 | prefill 0054 | change | mean decode 0053 | mean decode 0054 | change |
  | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
  | 4k | 1197.4 | 1279.6 | +6.9 % | 97.0 | 95.4 | -1.6 % |
  | 32k | 1019.6 | 1081.8 | +6.1 % | 102.6 | 102.8 | +0.2 % |
  | 128k | 582.5 | 601.6 | +3.3 % | 55.1 | 54.8 | -0.5 % |

  ("prefill" is the code prompt at each depth; "one sync per K write" warnings 0.)
- **Verdict.** Pass.
- **Receipts.** `docs/receipts/release_0054.log`.

## G08 Bundle and publish (2026-10-13 21:00-)

- **Zip.** `bonsai-bundle-win-x64-20261013.zip`: the 66-entry layout of bundle-20261011; engine binaries from the
  release build (`LLAMA_COMMIT de873117e1`), byte-identical to the gated `/tmp/root-0054/bin`; every other file
  from `git archive` of the release commit `0cb9bb98` (PR #51). 22 entries changed against bundle-20261011: 7 engine
  files, the README note, and the docs / receipts path move and doc edits since then (launcher: comments only).
  610,554,885 bytes, SHA-256 `dda336ab1473707724078e42f81e720cbf7c286954004db85827c602b03e5a51`.
- **Plan.** When G05-G07 pass: a zip from `git archive` at the release commit (the bundle-20261011 layout), release
  notes, the Hugging Face card (53 -> 54 patches), the README upgrade note; GitHub release and Hugging Face upload;
  SHA-256 checked on both; the bins installed in the product `bin/` (the old ones kept in `bin-20261011/`).
- **Status.** Waits for G05-G07.
