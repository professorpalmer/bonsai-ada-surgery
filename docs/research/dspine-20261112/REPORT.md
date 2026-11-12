# DSpine drafter research: report (2026-11-12)

DSpine (`tencent/Qwen3.8-27B-DSpine-b16`, a 5-layer block drafter for Qwen3.8-27B) on Bonsai 2 27B (PTQ1_0),
RTX 4070 12 GB, against the MTP head of the bundle and against no draft. Issue #258; idea from Milor123.
Plan and gate: `DS1-plan.json` (written before the first GPU run; amendment 1 written before the first speed cell).

## Bottom line

1. **Not adopted. The gate fails on prose at every depth.** With the best DSpine setting (q4_0, draft 15), code
   decode is +28 % / +9 % / +16 % over the MTP head at 1.5k / 16k / 32k, but prose decode is -41 % / -44 % / -33 %.
   On prose the drafter accepts 8-11 % of its 15 tokens, and every rejected token is a verify column that costs time.
   With draft 3 the loss on prose is smaller (-9 % to -25 %), but code is then no faster than the MTP head.
2. **The plain DSpine file does not work on Bonsai 2: acceptance 0.5 %.** A DFlash-family draft without its own
   output head uses the target's head, and the head of Bonsai 2 is ternary. The same file on the full-precision
   Qwen3.8-27B accepts 91 % of its drafts (DS0b), so the engine port is correct. With the Qwen3.8-27B output head
   (Q6_K, 1.0 GB) put into the draft file, the acceptance on Bonsai 2 is 80 % on a short code prompt (DS0c).
   The Qwen token embeddings make no difference.
3. **VRAM: DSpine q4_0 with the head takes about 1.96 GB more than the MTP head** (q8_0: about 2.9 GB more).
   In the 262k tiered product that moves the VRAM line down by about 59k cells (estimate, from the launcher's
   34,816 bytes per q8_0 cell). All-VRAM context with q8_0 KV on this card: about 175k (no draft), 150k (MTP),
   90k (DSpine q4_0), 60k (DSpine q8_0) (estimates from the free VRAM after load at 40k; not tested).
4. Greedy output with DSpine is the same text as without a draft, or it changes late at one near-tie token
   (first difference at character 249 or later of 1,568-2,229). That is the same class of difference as the MTP arm
   (`bt`) shows. No broken or repeated text.

## Results (decode tok/s, greedy, 400 tokens, mean of 2 requests; fresh server per cell)

DSpine arms use the Qwen3.8-27B output head (amendment 1). `b` = MTP head as shipped (its model file carries the
bundle's chat template); `bt` = the same with the template of the other model file, so its prompt tokens are equal to
the other arms. `b` and `bt` are within 5 % of each other in every cell (noise). Mean accepted length = tokens per
verify step, from the server log.

| arm | 1.5k code | 1.5k prose | 16k code | 16k prose | 32k code | 32k prose |
| --- | --- | --- | --- | --- | --- | --- |
| a: no draft | 58.0 | 57.9 | 54.5 | 54.6 | 50.6 | 50.6 |
| b: MTP head, draft 2 (shipped) | 98.7 | 79.9 | 94.7 | 77.2 | 86.9 | 70.5 |
| bt: b, same template as the others | 100.6 | 78.6 | 96.4 | 77.0 | 91.0 | 69.3 |
| DSpine q4_0, draft 15 | **126.6** (+28 %) | 46.8 (-41 %) | 102.9 (+9 %) | 43.1 (-44 %) | 101.0 (+16 %) | 47.4 (-33 %) |
| DSpine q8_0, draft 15 | 118.8 (+20 %) | 46.4 (-42 %) | 100.6 (+6 %) | 42.2 (-45 %) | 96.8 (+11 %) | 44.9 (-36 %) |
| DSpine q4_0, draft 3 | 104.0 (+5 %) | 67.5 (-16 %) | 91.9 (-3 %) | 58.0 (-25 %) | 87.8 (+1 %) | 64.5 (-9 %) |
| DSpine q8_0, draft 3 | 96.7 (-2 %) | 62.6 (-22 %) | | | | |
| DSpine q4_0, draft 7 | 83.3 (-16 %) | 37.1 (-54 %) | | | | |
| DSpine q8_0, draft 7 | 78.6 (-20 %) | 35.3 (-56 %) | | | | |

Percentages are against `b` at the same depth and prompt. Draft 7 and the q8_0 draft 3 arm ran at 1.5k only: the
plan takes the arm with the best mean of code and prose per quant to the deeper cells (draft 15 for both quants);
q4_0 draft 3 was added as the most even arm.

Acceptance (first request of each cell):

| arm | code: accept % | code: mean accepted length | prose: accept % | prose: mean accepted length |
| --- | --- | --- | --- | --- |
| b: MTP head, draft 2 | 80-83 | 2.59-2.65 | 54-58 | 2.07-2.16 |
| DSpine q4_0, draft 15 | 30-35 | 5.45-6.23 | 8-11 | 2.19-2.55 |
| DSpine q8_0, draft 15 | 30-34 | 5.47-6.14 | 8-10 | 2.27-2.49 |
| DSpine q4_0, draft 3 | 77-80 | 3.30-3.40 | 36-46 | 2.08-2.38 |
| DSpine draft 7 (1.5k) | 58-60 | 5.05-5.18 | 18 | 2.22-2.27 |

VRAM used after load, server only, ctx 40,960 with q8_0 KV:

| arm | MiB | vs b |
| --- | --- | --- |
| a: no draft | 7,208 | -850 |
| b: MTP head | 8,058 | 0 |
| DSpine q4_0 + head, draft 3 / 15 | 9,928 / 10,018 | +1,870 / +1,960 |
| DSpine q8_0 + head, draft 3 / 15 | 10,894 / 10,984 | +2,836 / +2,926 |

Prefill: 1,016-1,147 tok/s with DSpine, 1,116-1,235 with the MTP head, 1,166-1,310 without a draft (the draft
also encodes the prompt). The memory clock was 10251 MHz (stock) in every cell.

## Decisions

| item | decision | why |
| --- | --- | --- |
| DSpine as the bundle drafter (q8_0 or q4_0, any draft size) | **rejected** | gate: prose is 9-56 % slower than the MTP head at every depth and draft size; code gains (draft 15) do not cover it |
| plain DSpine file on Bonsai 2 | **rejected** | 0.5 % acceptance: the ternary output head breaks it (DS0a, DS0c) |
| DSpine + Qwen3.8-27B head, code-only use | not shipped | +9 to +28 % on code only, +1.96 GB VRAM, -41 % when the text turns to prose; it would need a content switch |
| engine port (DSpine + DFlash causal flag) | kept on the fork, branch `research/dspine` | correct on the full-precision target (DS0b); no bundle change |

## Lessons

1. **A drafter that borrows the target's output head fails on a ternary target.** Bonsai 2's head is ternary
   (PTQ1_0). DSpine's last hidden state goes through that head, and the drafts become almost random (0.5 %). A
   full-precision head in the draft file restores 80 %. Check this first for any DFlash-family drafter on Bonsai.
2. **Long drafts cost much on prose.** The verify step of a 16-token block is not free on this card, and on prose
   DSpine predicts only ~2.2 tokens per step. The MTP head with draft 2 predicts ~2.1 per step at a much lower cost.
3. **Draft 7 was slower than both draft 3 and draft 15**, also on code with 5.1 accepted tokens per step. A likely
   cause (not measured) is a kernel change for the ternary mat-vec between 8 and 16 batch columns. A profile of the
   verify step at 4, 8 and 16 columns would show it.
4. The two model files of the bundle carry different chat templates, so text comparisons against the MTP arm need
   the same template (`bt`).

## Open items

1. The output head in the test files came from a Q4_K_M GGUF of Qwen3.8-27B (Q6_K head). A clean file would take
   `lm_head.weight` from the Qwen3.8-27B safetensors and quantize it (q4_0 would save about 0.3 GB more; not tested).
2. A DSpine fine-tune on Bonsai 2 hidden states (with Bonsai's own head) could fix the head problem and the low prose
   acceptance. Not in scope here.
3. Adaptive draft length (long drafts while the acceptance is high, short drafts on prose) could keep the code gain
   without the prose loss. The engine has no such switch for DFlash drafts.
4. Not tested: the 262k tiered-KV launcher with DSpine, the bundle's sampling settings (temperature 1.0), thinking on.
