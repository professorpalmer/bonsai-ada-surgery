# Experiments: cold read-in (4070 side)

All runs on the RTX 4070 12 GB, driver 610.88, memory clock 11,751 MHz under load. The 8 GB-like recipe pins the VRAM
line at 80,640 cells with q3_0 K/V (the 2060 line), so a deep prompt sits mostly in the host tail.

## T2a: prefill attention with 2 Q heads per column group (2026-10-16 04:08-04:31)

- **Plan** (kernel session, script header, before the run): kernel fork `t2-prefill` 2724a8349 = 0059 +
  `GGML_CUDA_FA_PREFILL_NCOLS2=2` (default 8). With GQA 6 the MMA kernel packs 8 Q-head columns per KV head, 2 of them
  padding; packing 2 heads x more tokens loads each K/V tile less often. Gates: FLASH_ATTN_EXT op tests 0 FAIL; answers
  byte-identical (d27_hash, 3 prompts, temp 0); then the prefill rate at 32k / 64k / 128k, alternated x2.
  Script: `scripts/t2a_ncols2.sh`.
- **Result:** op tests 3115/3115 in both arms. **Identity fails:** prompt 1 is identical, prompts 2 and 3 differ
  (prompt 2: 710 vs 592 tokens). Prefill, code prompt, both repeats agree: 32k 1,144 -> 1,170 tok/s (+2.5 %), the
  32k-64k chunk 857 -> 892 (+4.2 %), the 64k-128k chunk 618 -> 653 (+5.6 %). quick_tps reuses the cache between depths
  on one server, so only the 32k row is a cold read. Decode 2-5 % lower, confounded by the different outputs (draft
  acceptance). Receipt: `docs/receipts/prefill_ncols2_t2a.log`.
- **Cause (kernel session, corrected on #138 comment 6214090726):** ncols is the same in both arms (32 on Turing, 64 on
  Ada). The switch changes the number of Q tiles, and with it the stream-k split of the KV range across blocks, so the
  partial sums are combined in a different order. At best PPL-equal, not byte-identical. (A first reading, a change of
  the K/V tile length per softmax step, was wrong.)
- **P154 on the 2060 (sm_75, #138 comment 6213954510):** cold 64k 1.067x, cold 128k 1.110x, decode equal, the 4k code
  answer byte-identical. The declared rule asked for >= 10 % at 64k and 128k, so T2a as declared does not pass.
- **T2a-2** (a new plan, sm_75 only, #138 comment 6214090726): Q1 PPL + KL at 4k / 16k (KL <= 0.001, top-1 >= 99.5 %,
  PPL within +-0.2 %), then Q3 a cold 245k pair (>= 1.10x), then Q2 n24 / n28 / copies at 245k vs the 2060 default; stop
  at the first fail. Runs on the 2060.

## T2b-1: MMQ column-tile cap for the PTQ1_0 prefill matmuls, 4070 control (04:31-04:47)

- **Plan** (kernel session, script header, before the run): `-Xptxas -v` shows the PTQ1_0 MMQ instance spills on sm_75
  at J >= 64 (255 registers; J 128: 112-136 B, J 64: 24-72 B; none at J <= 48) and does not spill on sm_89. Engine `t2-prefill` 5bb256bb4 adds
  `GGML_CUDA_MMQ_MAX_J` and 12 PTQ1_0 prefill perf cases. The 4070 run is the control (no gain expected). Gates: G1 op
  tests 0 FAIL per J; G2 per-op perf sum >= 3 % better in both repeats; G3 prefill at 4k / 16k / 32k, same rule.
  Script: `scripts/t2b_maxj.sh` (the version as run; see the parse note).
- **Result:** G1 0 FAIL at J 128 / 64 / 48. G3, code prompt (4k cold; 16k and 32k are chunks at depth): J128 1,280 /
  1,212 / 1,042 tok/s, J64 1,124 / 1,064 / 933 (-12 %), J48 1,026 / 972 / 861 (-20 %). Answers change with J (stream-k
  split), as the header says. Receipt: `docs/receipts/prefill_mmq_maxj_t2b.log`.
- **Parse note:** the "G2 sum us/run" lines in the receipt hold ONE case only (m=12288 n=2048 k=5120): the CUDA graph
  log on stderr split each timing line. Recomputed from the saved logs over all 13 cases (kernel session, #138
  comment 6212813590): J128 20,412 / 20,459 us, J64 24,328 / 24,329 (+19 %), J48 27,580 / 27,617 (+35 %). The script was
  fixed for the 2060 run.
- **Reading:** a control as expected. The test that counts is the 2060 (sm_75), where J 48 removes the spills and J 64 reduces them.

## T1-a: slot save / restore, then the same request again (04:48-05:23)

- **Plan** (#138 comment 6212170839, before the run): bundle-20261016 bins (ab94810051), q3_0, line pinned 80,640,
  layer off; launcher = the product start-server.ps1 + one test-only line that passes `--slot-save-path`. Per depth:
  server 1 request A + save; server 2 (fresh) restore + the same request B; at 64k and 245k server 3 with no restore (C).
  Gates: G1 no error; G2 B == A (valid where C == A); G3 prompt_n after restore <= 512; G4 restore + prompt time <= 30 s
  at 245k. Scripts: `scripts/t1_slot.sh`, `scripts/t1_slot.py`.
- **Result: G3 fails.**

  | depth | first read | save / file | restore | after restore: prompt_n / time | B = A |
  | --- | --- | --- | --- | --- | --- |
  | 64k | 68.2 s | 0.81 s / 1,051 MiB | 0.47 s | 65,732 / 68.3 s (all again) | yes (C = A) |
  | 128k | 177.8 s | 1.78 s / 1,939 MiB | 0.96 s | 130,608 / 177.8 s | yes |
  | 245k | 468.5 s | 3.29 s / 3,494 MiB | 1.72 s | 244,128 / 468.5 s | yes (C = A) |

- **Reading:** the files save and load at ~2 GB/s, but the repeat request reads the whole prompt again. The saved
  state ends after the 81 answer tokens; a repeat must roll back past them, and the 48 GDN layers keep a recurrent state
  that cannot roll back without a context checkpoint. The checkpoints are held in RAM and are not in the slot file.
  Receipts: `docs/receipts/t1_slot_restore.log` / `.jsonl`.

## T1-b: slot save / restore, then continue the conversation (05:24-05:47)

- **Plan** (#138 comment 6213052399, before the run): same recipe and root. Per depth: server 1 request 1 (A), save,
  then request 2 = request 1 + A as the assistant turn + a new question (D2, the in-memory continuation); server 2
  (fresh) restore + request 2 (B2); at 64k and 245k server 3 with no restore (C2, reported only). Gates: G1 no error;
  G2 B2 == D2 byte for byte; G3 prompt_n of request 2 after restore <= 1,024; G4 restore + prompt time <= 30 s at 245k.
  Scripts: `scripts/t1b_slot.sh`, `scripts/t1b_slot.py`.
- **Result: all gates pass.**

  | depth | first read | save / file | restore | request 2 after restore: prompt_n / time | B2 = D2 | C2 (full read) |
  | --- | --- | --- | --- | --- | --- | --- |
  | 64k | 68.2 s | 0.82 s / 1,051 MiB | 0.49 s | 32 / 0.28 s | yes | 65,845 tokens, 68.4 s, same answer |
  | 128k | 177.7 s | 1.84 s / 1,939 MiB | 0.93 s | 32 / 0.32 s | yes | not run |
  | 245k | 468.4 s | 3.30 s / 3,494 MiB | 1.69 s | 32 / 0.52 s | yes | 244,241 tokens, 468.7 s, same answer |

- **Reading:** the existing slot save / restore works with the tiered KV cache and the GDN / conv states when the next
  request extends the saved tokens: at 245k, 2.2 s against a 468 s read on this card (the 2060 reads 245k in ~1,695 s;
  the file is the same size there). T1-a's failure is the rollback case only (the same request again, or an edited
  history). Receipts: `docs/receipts/t1b_slot_continue.log` / `.jsonl`.
- **Next (proposal on #138):** a launcher switch for `--slot-save-path`; automatic save after large requests to a file
  named by a hash of the tokens, and a restore of the longest saved prefix on a fresh server; context checkpoints in the
  slot file for the rollback case.

## The 2060's T1 runs (by the 8 GB tester, #138; receipts in its receipts/p15x/)

- **P153** (T1-b on the 2060, thinking off): restore + continue 64k 1.12 s + 0.73 s, 128k 1.93 + 0.82, **245k 3.41 + 1.82 s
  = 5.2 s instead of a 1,689 s read**; answers byte-identical. Thinking on: the template drops the reasoning from the
  history, the request diverges inside the saved answer and reads everything again.
- **P155 / P155b** (layer T1-c v1 / v2): v2's save point (the end of the last message, before the generation prompt)
  restores in both thinking modes. After a restore, a multi-ubatch continuation crashed (`ggml-cuda.cu:109`,
  intermittent) or read at ~12 tok/s.
- **P157 / P157b:** the slowdown is deterministic and only on a fresh server; at 64k: defaults 165.6 s for 3,969 new
  tokens, `BONSAI_LOOKUP=0` the same, **`BONSAI_SPEC=0` 18.7 s**. Cause: the slot file held the target context only; the
  MTP draft context started empty in a fresh process. (The 4070 never showed the slowdown with the same server code.)

## T1-e / T1-f / T1-g: the 2060's restore failure does not reproduce on the 4070 (08:32-11:04)

- **T1-e** (8 GB preset, 131k, a 5,478-token new turn; arms default / calib file moved aside / `BONSAI_SPARSE=0`; plan on
  #138 before the run): restore 0.88-0.90 s, new turn 11.1-11.2 s (= in memory 11.3 s), answer equal, 0 CUDA errors in
  all arms. Receipt `t1e_restore_long.log`.
- **T1-f** (the same with `GGML_CUDA_GDN_MMA_DISABLE=1`: the recurrent GDN kernel with K 2 snapshot slots, the sm_75
  path): restore 0.94 s + 11.5 s, no error, answer equal. The recurrent-GDN theory is out on sm_89. Receipt
  `t1f_recurrent_gdn.log`.
- **T1-g** (VRAM trace; GPU Process Memory counters): a restored server does not hold more VRAM (peak 8,019 vs 8,049
  MiB; shared 2,604 MiB in both = the pinned host tail). Part 2, a torch ballast leaving 7.06 GB free: a plain cold
  read crawled at ~40 tok/s (shared +950 MiB: the Windows sysmem fallback spill), so it was stopped (no restore-specific
  reading possible). Side finding for the backlog: VRAM that grows after launch silently slows the server 10-20x.
  Receipt `t1g_vram.log`.

## T1-h: the MTP draft-context sidecar (11:37-11:49)

- **Fix** (kernel session, kernel fork `product-slotdraft` **303f01131** = product-0059 + two server commits): the slot
  save also writes the draft context's sequence state to `<file>.draft`; restore loads it; with no sidecar it clears
  the draft sequence and warns.
- **Plan** (#138, before the run): both files written; restore logs `draft context state restored`; answer = in memory;
  speed within 10 %; without the sidecar the warning; no CUDA error.
- **Run 1 void:** "restored (12 bytes)": the first commit made only the header probe call of
  `llama_state_seq_load_file`, so nothing was loaded (fixed in 303f01131). Receipt `t1h_slotdraft_run1_void.log`.
- **Rerun: all gates pass.** `.draft` 15,007,796 B; `draft context state restored (15007796 bytes)`; restore 1.00 s +
  11.22 s, answer = in memory; without the sidecar `no draft context state ... (the draft context starts empty)`, same
  answer; 0 errors. The 4070 never showed the slow path, so the 2060's P158 is the test of the speed fix. Receipt
  `t1h_slotdraft.log`.

## T3: block-sparse prefill attention (kernel session's plans on #138; 4070 runs 07:40-12:49)

| step | what | result | receipt |
| --- | --- | --- | --- |
| Q0 | emulation, per 64-query tile, keep 1/4 of the far pages; n24 / n28 / copies at 245k vs dense | **fail**: n24 loses vault 15 (gains 14); stopped after n24 | `t3_q0_prefill_sparse.log` |
| Q0a | per query, 1/4 | **fail**: n24 loses vault 6 | `t3_q0ab_prefill_sparse.log` |
| Q0b | per 64-query tile, **1/2** | **pass** on all three sets: n24 24/24 (gain 14), n28 27/28 (miss 15 = dense; gains 19, 24), copies 19 / 20 = dense | `t3_q0ab_*`, `t3_q0b2_prefill_sparse.log` |
| S0 | 8k KL of the speed path (two void runs: a missing tool DLL; the RAM guard stopped a 16k base at 31 GB) | keep-all arm KLD 0 / top 100 % (correct); 1/2: KLD 0.0027, top 97.8 %; 1/4: 0.011, 96.1 % | `t3_s0_kl.log` |
| S1 | first speed path (+ the per-tile skip map, 5225e138c), cold reads | part 1: the map changes nothing (1/2 with and without it: KLD 0.002740); slower than dense: 128k 0.79x, 245k 0.64x (the per-(page, query) score kernel) | `t3_s1_speed.log` |
| S2 | tiled score kernel | 128k **1.07x** (rule 1.10x: not met); scores 42.8 -> 2.7 ms per op | `t3_s2_speed.log` |
| S3 | split by stage, 245k | **245k 1.159x** (526.0 -> 609.8 tok/s, 463.7 -> 400.0 s): rule 1.15x **met**; to the 2060 for a speed probe | `t3_s3_split.log` |
| S4 / S5 | per-tile skip map: diagnostics | the map is built (mean visible 0.667); Nsight Compute: -21.8 % kernel time per deep launch; S4's -7 % was diluted by dense ops below the VRAM line | `t3_s4_vis.log`, `t3_s5_ncu.log` |

Q0 / Q0a / Q0b ran the quality-only emulation (a per-query mask on the dense kernel), not the speed path; the speed
path's own item gates are still open (2060). The "T3 engage lines: 0" in Q0 means a filtered INFO line; the sparse op counter showed 5,121 prefill-only ops.

## P152 (2060): the full window is free up to 128k

BONSAI_CTX 131,072 vs 262,144, alternated x2: decode within 1 % at 4k / 64k / 96k / 128k (52.6 / 40.5 / 35.2 / 22.4
tok/s), prefill equal. Docs can say: the full 262k window costs nothing up to 128k; only filling it is slow.
