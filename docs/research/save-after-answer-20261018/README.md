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
