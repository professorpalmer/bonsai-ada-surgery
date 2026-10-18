# Save after the answer (#138, layer cache)

Date: 2026-10-18. Hardware: RTX 4070 12 GB. Branch: `cache/save-after-answer`.

## Problem

The layer cache (`layer/slot_cache.py`) saves a conversation BEFORE the request: a prefill-only call reads the prompt up to
the end of the last message, the slot is saved, and then the real request runs. This has three costs:

1. The user waits for the save (several GB to disk) before the answer starts.
2. The prefill-only call reads the new tokens in other batch splits than without the cache, so greedy output can differ by
   a token at a turn that saves (P160 turn 4).
3. After a restart, the restored state ends before the last answer, so the first request reads the last answer and the
   new turn again.

G1 (`docs/receipts/grow_ab*`, 30-turn agent session, 131k document, restart before every 3rd turn): restart turns took
37.8 s on average and normal turns 11.5 s (GROW 8192).

## Change

`BONSAI_SLOT_CACHE_AFTER=1` (default 0 until the gates below pass):

- After each answer, the layer reads the slot token count (`GET /slots`, `n_prompt_tokens`).
- At the next turn of the same conversation, the cached-token count in the server reply (`timings.cache_n`) tells whether the
  state after the answer was a prefix of the new prompt. This test writes no file.
- When the test passes, the conversation saves AFTER the answer (when it grew by GROW or more since the best saved
  prefix) and does not save before the request. The client has the whole answer before the save starts.
- The saved token list comes from the slot file header (`llama_state_seq_save_file`: magic `ggsq`, version 2, count,
  tokens). Thus a restore is exact also when the answer tokens differ from a new tokenization of the answer text.
- When the test fails (the template or the client drops or rewrites the answer, for example a client that does not send
  the reasoning back), the conversation uses the save before the request again. The result per conversation is kept in
  `lc-conv.json`, so a restarted layer keeps it.
- `GET /layer/slot-cache` returns `{"on", "after", "busy"}`. A stop script can wait while `busy` is true.

Template check (Bonsai template, 4070 server): a past answer renders as `<think>\n\n</think>\n\nA1` with thinking off,
the same as the generation prompt plus the answer. With thinking on and `reasoning_content` sent back, it renders
`<think>\nR1\n</think>\n\nA1`. Without `reasoning_content` the reasoning is dropped, and the test fails.

## Offline tests

`tests/test_slot_after.py` (fake server with a token-list slot): pass, then after mode, save after the answer, restore
after a restart with no prefill-only call; a rewritten answer fails the test and goes back to the save before; another
conversation between two turns does not count as a result; a slot that changed before the save gives no file and no index
entry; off by default; the layer hook runs `after()` once the answer is out. `tests/test_slot_cache.py` passes unchanged.

## GPU A/B (declared before the run)

Harness: the G1 session (`p155_turn.py`, 131k document, 30 turns, thinking off, 8 GB preset, cells 80,640, GROW 8192),
the server and layer restarted before turns 1, 4, 7, ... 28. Before each restart the harness waits until
`/layer/slot-cache` says `busy: false` (both arms, max 180 s) and logs the wait. Arms: `after` (AFTER=1) first, then
`before` (AFTER=0, the shipped path). A fresh slot folder per arm.

| Gate | Condition |
|---|---|
| A answers | the 30 `after` answers equal the 30 `before` answers |
| B restart turns | mean wall time of restart turns 4 ... 28 (9 turns) at least 30 % lower in `after` |
| C normal turns | mean wall time of the 20 normal turns not more than 10 % higher in `after` |
| D session | arm wall time (start to end, restarts and waits included) not higher than `before` + 5 % |
| E mechanism | the prefix test passes in the layer log; at least 1 save after the answer; saves in `after` not more than `before` + 2 |
| F health | 0 CUDA errors; no `lc-saving-*` files left |

All pass: merge, then make AFTER the default in the next bundle and port it to Mirai. Any fail: keep it off and log why.

## Runs

(entries below, one per run)

### Run 1 (VOID): the test read a counter the server resets

The prefix test read `n_prompt_tokens_cache` from `GET /slots`. The server resets its per-request counts when the task
ends, so the value was always 0 (`void_run1_slots.log`). Fix: the layer reads `timings.cache_n` from the reply it relays
(all reply paths: plain, streamed, interpreter stream).

### Run 2 (VOID): two harnesses at the same time

The stop of the run-1 task ended only its wrapper. The run-1 script kept running (turns 10-13) against the same port
while run 2 started. Both were killed by process ID (files in `void/`).

### Run 3: after arm INVALID, before arm = the baseline

The slot file header holds the server's packed `server_tokens` state (`0xffffffff`, version 1, count, tokens, media
count), not a plain token list. The reader took it as a plain list, so every save after the answer failed its own token
check (no wrong file was written). Fixed; the reader agrees with the `.tok` file on 13 real slot files of both arms.

Before arm (the shipped path, receipts in `run3/`): restart turns 4-28 mean 72.5 s, normal turns 11.5 s, arm wall
1,291 s, 30/30 answered, 0 CUDA errors, 6 files.

The after arm without any save after the answer still showed: restart turns 34.9 s (-51.9 %), but normal turns 23.3 s
(+101.9 %), because each failed save attempt still wrote a file and then deleted it, while the next turn waited.

The prefix test: 8 pass, 12 fail. Every fail was short by (answer tokens + about 7).

### Diagnosis: n-gram drafts continue past the end of the answer (`diag.py`, `diag_spec.jsonl`)

A 20k-token conversation, 10 turns, direct to the server, with `return_tokens`:

- On all 10 turns, the generated tokens are the same as the tokens of the answer that the next turn renders
  (`gen_vs_rendered_first_diff: null`). Tokenization is not the cause.
- Turns 2-7: `cache_n` = the slot size after the previous answer (the test passes).
- From turn 7, the n-gram drafter proposes 32-token drafts. Turn 8: 7 draft tokens accepted for a 6-token answer. The
  draft continued past `<|im_end|>`, the target accepted those tokens and read them into the slot. The next turn differs
  there, so the server falls back to a context checkpoint about 4 tokens before the end of the previous prompt (the test
  fails).

The state stays consistent with the slot token list, so a file saved there is safe (its tokens include the extra ones,
so it is never a prefix of a later prompt). It is only useless.

Fix: fork patch 0067 (`serve/draft-stop-at-eog`, c5e73e7d81 on the product commit 96f6e49cdc): a speculative draft stops
at its first end-of-generation token. Gate for 0067: `diag.py` with the patched server gives `cache_n` = the previous slot
size on all turns, and the same 10 answers as without the patch.
