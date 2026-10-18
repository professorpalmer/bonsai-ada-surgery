# A speculative draft stops at the end of the answer (patch 0067)

Date: 2026-10-18. Hardware: RTX 4070 12 GB, 8 GB preset (cells 80,640). Found during the save-after-answer work (#138,
`docs/research/save-after-answer-20261018` on branch `cache/save-after-answer`).

## Problem

The n-gram drafter (`ngram-mod`, up to 32 tokens) continues a draft past `<|im_end|>`: in a long conversation the history
makes `<|im_end|>\n<|im_start|>...` easy to predict. The target accepts those tokens and reads them into the slot. The
next turn of the conversation differs inside them, so the server cannot reuse the state after the answer: it falls back to
a context checkpoint about 4 tokens before the end of the previous prompt and reads the answer again. A slot file saved
after such an answer is never a prefix of the next prompt.

## Change

Fork commit c5e73e7d81 (`serve/draft-stop-at-eog`, on the product commit 96f6e49cdc), `tools/server/server-context.cpp`:
a speculative draft stops at its first end-of-generation token (`llama_vocab_is_eog`). The draft keeps that token, so an
accepted end token is read into the slot as `<|im_end|>`, which the next turn's prompt also has at that position.

## Measurement (`diag.py`)

A 20k-token conversation, 10 turns, thinking off, greedy, direct to the server (no layer). `cache_n` of each turn against
the slot size after the previous answer:

| | turns with `cache_n` = previous slot size | answers | drafts turns 7-10 (drafted / accepted) |
|---|---|---|---|
| product 96f6e49cdc (`diag_spec.jsonl`) | 6 of 9 (turns 8-10 short by 13-17 tokens) | | 32/11, 32/7, 32/11, 32/9 |
| + 0067 c5e73e7d81 (`diag_0067.jsonl`) | **9 of 9** | **10/10 the same** | 9/9, 5/5, 9/9, 5/5 |

The generated tokens were the same as the tokens of the rendered answer on all turns in both runs, so tokenization is not
the cause.

## Effect

- In memory: the next turn reuses the whole state after the answer (before: it read the last answer again from a
  checkpoint, a few dozen tokens).
- The target no longer verifies draft tokens after the end of the answer.
- Saved conversations: the state after an answer can be a prefix of the next turn (the save-after-answer work needs this).
