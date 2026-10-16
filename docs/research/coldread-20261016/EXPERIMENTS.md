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
- **Cause and decision (kernel session):** the MMA config is chosen per ncols; for head 256 it changes the K/V tile
  length per softmax step (nbatch_fa), so the rescale points and the accumulation order move. At best PPL-equal, not
  byte-identical. No more 4070 time: if the 2060 (P154) shows >= 10 % cold prefill at 64k / 128k, a T2a-2 plan with PPL,
  KL, items and decode with MTP off comes first; otherwise T2a is closed.

## T2b-1: MMQ column-tile cap for the PTQ1_0 prefill matmuls, 4070 control (04:31-04:47)

- **Plan** (kernel session, script header, before the run): `-Xptxas -v` shows the PTQ1_0 MMQ instance spills on sm_75
  at J >= 80 (255 registers, 112-136 B) and does not spill on sm_89. Engine `t2-prefill` 5bb256bb4 adds
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
- **Reading:** a control as expected. The test that counts is the 2060 (sm_75), where the cap removes the spills.

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
