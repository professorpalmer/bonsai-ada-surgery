# Experiments S01-S06

Gates in `README.md` (written before the runs). Engine `product-0056` `b86298dba9` (= bundle-20261014's `4de6185494` +
0056 q3_0 + 0057 packed-half dequant), release build sm 75 / 86 / 89 (`LLAMA_COMMIT b86298dba9`), root `/tmp/root-0056` =
the bundle-20261014 zip + these bins + main's launcher (`07538d1`, with the q3_0 cell size from #83). RTX 4070, memory
clock 11751 MHz under load, driver 610.88. The PR #88 patch files applied on `4de6185494` give tree `bb92bcff`, the
same tree as the build.

---

## S01 Op tests (16:24-16:27)

- `FLASH_ATTN_EXT` 3115/3115, `GATED_DELTA_NET` 55/55, `SET_ROWS` 177/177, `CPY` 259/259, `GET_ROWS` 123/123; 0 FAIL.
  **Pass.**

## S02 12 GB same text (16:27-17:24)

- HumanEval 164 at medium on the bundle's binaries: 158/164; **164/164 answers identical** to bundle-20261014 (the
  b0055 run on the same bins as that bundle); 0 test-process failures. 0057's q8_0 dequant (the 12 GB default) is
  bit-exact. **Pass.**

## S03 12 GB speed (17:24-17:32)

- `bench/depth_arms.sh bench/arms/release_0056.txt` (tag rel0056), product `bin/` (bundle-20261014) vs root-0056:

  | depth | prefill 1014 | prefill 0056 | mean decode 1014 | mean decode 0056 |
  | ---: | ---: | ---: | ---: | ---: |
  | 4k | 1278.8 | 1285.0 (+0.5 %) | 95.4 | 96.5 (+1.2 %) |
  | 32k | 1084.9 | 1084.9 (0.0 %) | 101.7 | 102.3 (+0.6 %) |
  | 128k | 607.7 | 611.3 (+0.6 %) | 74.3 | 74.7 (+0.5 %) |

  **Pass** (all within 2 %, all at or above bundle-20261014).

## S04 8 GB default rule (RTX 2060 SUPER, P129 / P130 / P131 on `b86298dba`, by the 8 GB tester)

| rule item | result | record |
| --- | --- | --- |
| 1. 64k decode q3_0 within 5 % of q4_0 (alternated x2, same session) | 41.0 vs 39.6, **+3.5 %** | P130 |
| 2. perplexity at 16k at most +1 % | **+0.56 %** (7.9491 vs 7.9050); 64k +0.03 %; identical to P108 to 4 decimals | P129 |
| 3. HumanEval 164 at least 157 | **163/164** (HumanEval/93 fails) | P131 |
| 4. 160k copies / needles = q4_0 | q3_0 10/10 + 12/12 = q4_0 10/10 + 12/12 | P130 |

- Sweep (one server per type): 4k -1.8 %, 64k -1.7 %, **128k +44 %**, **192k +34 %**; line 80,640 vs 61,696 cells
  (1.31x); trace minimum free >= 91 MiB; 0 one-token answers. q3_0 op tests (SET_ROWS 14/14, GET_ROWS 4/4, CPY 7/7,
  FLASH_ATTN_EXT 110/110) pass on sm_75.
- The tester reads 163/164 as no loss on code, not a gain (greedy runs flip near-tie items).
- **Verdict: pass.** By the rule written before the runs, q3_0 becomes the 8 GB default (#91).

## S05 8 GB q4_0 under 0056 + 0057 (P140)

- `b86298dba` vs the `bundle-20261014` zip bins, q4_0 default switches, same session, alternated x2: answers identical
  11/11 in all four runs; mean decode **64k 35.7 -> 39.6 (+11.2 %), 128k 15.7 -> 16.9 (+7.6 %)**. On sm_75 the
  packed-half tile dequant removes more conversion work than on the 4070 (D28: +0.6 %).
- **Verdict: pass** (the gate was "not more than 2 % slower"; it is faster). Users who set `BONSAI_CTK=q4_0` get it.

## S06 Publish: bundle-20261015 (2026-10-15)

- PRs: #88 (0056 + 0057, `52bce80bc`) and #91 (q3_0 8 GB default, `7df4a098f`) merged by the kernel session; #95
  (sparse budget 1/8) before them; #102 README upgrade note -> release commit `0cbd0dcc`; #103 Hugging Face card.
- Zip: the bundle-20261014 layout (66 entries); engine bins from the release build (`LLAMA_COMMIT b86298dba9`, sm 75 /
  86 / 89), byte-identical to the gated `/tmp/root-0056/bin` (16 of 16); every other file from `git archive 0cbd0dcc`;
  12 entries changed against bundle-20261014 (README, the launcher, 10 engine files). 616,638,283 bytes, SHA-256
  `23db0bc477274314e817f3eaeda185b9ac314f31d346f45fc4861b2e3ae7dd16`.
- GitHub release `bundle-20261015` on `0cbd0dcc` (asset digest matches); Hugging Face zip `7639ca2`, card `28a57e3`
  (LFS oid matches, same size).
- Installed: the engine bins in the product `bin/` (`llama-server --version` commit `b86298dba9`, byte compare with the
  gated root OK); bundle-20261014 kept in `bin-20261014/`.
- **Verdict.** Published. The 2060's post-zip check (default launcher: q3_0 on 8 GB, no `BONSAI_CTK`) follows on #21.

## S06b The launcher bug and bundle-20261015b (2026-10-15)

- **Found by the 2060's post-zip check (P142, on #21):** the `bundle-20261015` launcher printed `window 262144 / q4_0`
  and line 61,696 with no `BONSAI_CTK`. Its q3_0 check was `$Help -match '<0x08>q3_0<0x08>'`: two backspace bytes
  where `\b` (word boundary) was meant, written by an escaped string in the final #91 revision. The pattern never
  matched, so 8 GB cards stayed on q4_0. No harm (the previous default), but the release's main change was not active.
  A repo-wide scan for control bytes found one more, older case: `layer<0x0C>etch_runtime.ps1` (a form feed) in two
  README lines since the first commit. Both fixed in #108 (reviewed on the 4070: the fixed pattern matches the 0056
  `--help` and not the 0055 one; the shipped pattern matched neither).
- **Why the gates missed it.** S01-S06 ran the engine on the 4070 with the 12 GB path and checked that the zip's
  launcher equals the release commit; nothing ran the 8 GB selection from the zip on this side. The 2060 ran the
  q3_0 rule items with a launcher test copy that set the type itself.
- **New gate, T1 (kept for every release from now on):** unzip, run the bundle's own launcher with `BONSAI_8GB=1` on
  the 4070 (and with `BONSAI_SPARSE=1` + a pinned line): the window line must name the 8 GB type, the sparse line must
  name the budget, one short request must answer. Also: no control bytes in tracked text files (`git grep -P`).
- **bundle-20261015b:** release commit `444de562` (#109 README note on top of #108); zip = the 20261015 zip with
  `README.md` and `start-server.ps1` from `444de562` (2 entries changed; engine bins the same), 616,638,401 bytes,
  SHA-256 `a6bf7adda3ed97de03a8105fb97b91afa68207544abea24e3b33572bb4035776`. T1 on the staged bundle: `window 262144 /
  q3_0`, replies OK; pinned line 80,640 + sparse: "budget max(B, host tail x 0.125) ... 153 MiB of page bounds"
  (`docs/receipts/release_0056b.log`). GitHub release `bundle-20261015b` (digest matches); the `bundle-20261015` notes
  now start with a superseded line; Hugging Face zip `29940a2` + card `ecda22d` (#110), LFS oid matches.
- **Verdict.** Published. The 2060 repeats the default-launcher part of P142 on the 15b zip.

## S07 bundle-20261015c: images in Responses API tool outputs (2026-10-15)

- **Bug (#112, reported by a user by DM):** an agent harness on `/v1/responses` whose browser tool returned a screenshot
  got HTTP 400 "Output of tool call should be 'Input text'", and every later request in that session failed (the item
  stays in the history). Reproduced on the 4070 with the shipped bins + mmproj. The chat-completions path accepted the
  same image in a tool message (the model named the colour).
- **Fix:** patch 0058 = ggml-org/llama.cpp `4098fdc922` cherry-picked (fork `product-0058` `c2cf6d645`, #113, kernel
  session). Gates (`docs/receipts/release_0058.log`), first on the test root, then on the staged zip: the Responses tool
  image is read ("red"); a text-only tool output is unchanged; a bad item type is a clean 400; the chat path is
  unchanged; op tests ADD 99/99, RMS_NORM 51/51, GET_ROWS 123/123, FLASH_ATTN_EXT 3115/3115; T1 (`BONSAI_8GB=1`):
  `window 262144 / q3_0`.
- **Build note.** The first release build failed at cmake generate: Windows temp cleanup had deleted sources in
  `%TEMP%\stock-adfffbe` again. `git checkout -- .` and a rebuild (`LLAMA_COMMIT c2cf6d6450`). `ggml-cuda.dll` is
  byte-identical to 0056; three other ggml DLLs differ in bytes after the full rebuild (no code change in them); the
  gates ran on these bins.
- **Published:** release commit `0d45cd03` (#114); zip = the 15b layout, 10 entries changed (README + 9 engine files),
  616,639,105 bytes, SHA-256 `a46ae100baef2ba38ad48a0a40c28c0e975d394e958e29dbe7b140a272f2560a`; GitHub
  `bundle-20261015c` (digest matches; 15b notes say superseded); Hugging Face zip `f0ecff7` + card `9f9b92c` (#116), LFS
  oid matches. Product `bin/` installed (`c2cf6d6450`; 15b bins kept in `bin-20261015/`).

## Status

- S01-S06 done: bundle-20261015 is published. P132 (sparse + q3_0) adds numbers but is not a rule item; the 2060's
  post-zip check follows. The bundle also carries #95 (`BONSAI_SPARSE=1` budget 1/8, R10 / R10b / R11 in
  release-20261014).
