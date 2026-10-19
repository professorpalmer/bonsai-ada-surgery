# Saved conversations

![Saved conversations on the RTX 2060 SUPER 8 GB: a 199k-token document read once in 1,069 s, then the first answer after a server restart in 5.3 s; a 131k document read ahead, then the question after a restart in 6.25 s against a 560.7 s cold read; a 30-turn session, restart turns 109.8 to 56.5 s. RTX 4070 12 GB with its default recipe: not measured](img/saved.png)

A long conversation costs a long read: on an RTX 2060 SUPER a cold 245k prompt takes about 1,489 s. With saved
conversations the server writes the conversation state to disk. After a restart, or when another conversation used
the slot, the next turn restores that state in seconds and reads only the new tokens.

## Turn it on

1. Set a folder for the slot files before you start the launcher:

   ```powershell
   $env:BONSAI_SLOT_SAVE_PATH = 'D:\bonsai-slots'
   .\start-server.ps1
   ```

2. Keep the layer on (the default). The layer saves and restores by itself for requests of 16k tokens or more.
3. Make sure that the drive has free space. At 245k one file is ~3.5 GB at q3_0 (8 GB default), ~4.5 GB at q4_0
   (12 GB default) and ~8.5 GB at q8_0. The layer keeps at most 20 GB (`BONSAI_SLOT_CACHE_GB`).

Needs `bundle-20261017` or later. Use the latest bundle: each bundle up to `bundle-20261018f` made the saves cheaper
(see [Upgrading](../build/UPGRADING.md)).

## Measured

RTX 2060 SUPER 8 GB, the zip's own launcher with its defaults (q3_0, 262k window, the display on the card). Records
in [`docs/research/depth-8gb-20261006/experiments/`](../research/depth-8gb-20261006/experiments/) and on
[#138](https://github.com/professorpalmer/bonsai-ada-surgery/issues/138).

| What | Without a saved state | With a saved state | Record |
| --- | ---: | ---: | --- |
| ~199k-token document, first question after a server restart | 1,069 s (the one cold read) | 5.3 s to the first token (restore 2.9 s) | P165, bundle-20261017, 2026-10-17 |
| the same document, later questions on the same server | | 2.5-2.6 s | P165 |
| 131k document read ahead (`"prefill_only": true`), question after a restart | 560.7 s (cold control) | 6.25 s (restore 1.84 s), the same answer | P162, 2026-10-16 |
| 30-turn agent session from ~131k to ~250k, restart before every third turn | | 30/30 answered, restores 2.05-3.36 s, 0 CUDA errors | P164, bundle-20261017, 2026-10-17 |
| the same session, save every 4,096 new tokens (8 GB default) instead of 8,192 | restart turns 109.8 s, session 2,266 s | restart turns 56.5 s (-48.5 %), session 1,842 s (-18.7 %), answers 30/30 the same | P200, bundle-20261018, 2026-10-18 |
| save after the answer (default since bundle-20261018b) | | answers 30/30 the same, session -2.3 % | P205, 2026-10-18 |

RTX 4070 12 GB: the restore was not measured with the 12 GB default recipe (q4_0, VRAM line 260,352). The 4070
runs of this feature used the 8 GB layout (q3_0, VRAM line 80,640), so they are not 12 GB numbers. They show the
mechanism: a 245k conversation restored in 1.69 s and the next turn read 32 tokens in 0.52 s, against a 468.4 s
first read ([coldread-20261016](../research/coldread-20261016/EXPERIMENTS.md) T1-b). On the same machine a full save
of a 173k conversation took 70.6 s on a slow drive and a delta save 0.08 s
([delta-saves-20261018](../research/delta-saves-20261018/README.md)).

## How it works

- **Save after the answer.** After each answer of a long conversation the layer saves the slot. The client has the
  whole answer before the save starts. The next turn restores exactly the state after the last answer.
- **Delta saves.** A save after an earlier save of the same conversation writes only the tokens since that save. A
  full save follows after 8 deltas (`BONSAI_SLOT_CACHE_CHAIN`). It runs when the layer has been idle for 30 s
  (`BONSAI_SLOT_CACHE_IDLE`), and after 32 deltas it is forced (`BONSAI_SLOT_CACHE_CHAIN_MAX`).
- **Several conversations.** Each conversation restores its own last save when conversations take turns. A save that
  would evict another conversation's save used in the last 10 minutes is skipped (`BONSAI_SLOT_CACHE_PROTECT`, 600 s).
- **Fallback.** When the next turn does not repeat the answer with the same tokens (for example, a client that does
  not send the reasoning back), the layer saves before the request instead. It tests this per conversation.
- **Read ahead.** A chat request with `"prefill_only": true` reads and saves a long prompt (a big file or a repo)
  before the question. Ask the question as a new message after it.

## Settings

| Variable | Default | |
| --- | --- | --- |
| `BONSAI_SLOT_SAVE_PATH` | off | the folder for the slot files; this turns the feature on |
| `BONSAI_SLOT_CACHE_MIN` | 16384 | the smallest prompt (tokens) that the layer saves |
| `BONSAI_SLOT_CACHE_GROW` | 8192 (8 GB preset: 4096) | new tokens since the best saved prefix before a new save |
| `BONSAI_SLOT_CACHE_GB` | 20 | disk budget of the folder |
| `BONSAI_SLOT_CACHE_GAIN` | 2048 | the smallest restore gain (tokens) |
| `BONSAI_SLOT_CACHE_AFTER` | 1 | 0 = save before the request (the design before bundle-20261018b) |
| `BONSAI_SLOT_CACHE_EVERY` | 1 | 0 = save only at `_GROW` steps, not after every answer |
| `BONSAI_SLOT_CACHE_CHAIN` / `_CHAIN_MAX` | 8 / 32 | deltas before a full save; deltas before a forced full save |
| `BONSAI_SLOT_CACHE_IDLE` | 30 | seconds of idle time before the full save runs |
| `BONSAI_SLOT_CACHE_PROTECT` | 600 | seconds in which another conversation's save is protected from eviction |

`GET /layer/slot-cache` returns `{"on", "after", "busy"}`. A stop script can wait while `busy` is true.

## Details

These are the details of the slot routes and the layer cache, as listed in the launcher settings before this page.

The folder holds slot files: `POST /slots/0?action=save` / `action=restore` with `{"filename": "name.bin"}`. A
restored conversation that continues reads only the new turn. The same request again re-reads the whole prompt.
Files are not removed automatically; at 245k a file is ~3.5 GB at q3_0, ~4.5 GB at q4_0, ~8.5 GB at q8_0 (scaled by
bytes per cell). The slot routes use the API key like the others, so a client with the key can fill the disk. On a
tight card, `GGML_CUDA_POOL_RESERVE_MIB=192` grows the CUDA memory pool at start (not needed on the measured 8 GB
card; #138).

With the layer on, saving and restoring is automatic (`layer/slot_cache.py`): for prompts of 16k tokens or more the
layer saves the conversation and, after a restart or when conversations alternate, restores the longest saved prefix
before the request (RTX 2060 SUPER: a 199k conversation answers in ~6 s after a restart, P160). Since
bundle-20261018b the layer saves after the answer instead of before the request (needs patch 0067;
`BONSAI_SLOT_CACHE_AFTER=0` goes back to the save before the request), when the next turn renders the answer with the
same tokens (thinking off, or a client that sends the reasoning back; the layer tests this per conversation and falls
back): no prefill-only call, and the client has the answer before the save starts. 4070 with the 8 GB layout, G1
session with restarts and 20 s of think time between turns (run 8): mean wait per turn -44 %, p95 wait 113 -> 71 s,
and the answers equal a session with the cache off on 30/30 turns (the save before the request flipped one near-tie
answer). Without think time the turn right after a slow save waits for it (run 5;
[`docs/research/save-after-answer-20261018/`](../research/save-after-answer-20261018/README.md)). With patch 0068 a
save after the answer writes only the tokens since the last save (a delta).

At a turn where the layer saves again, the new tokens are processed in other batch splits, so greedy output can
differ by a token there (P160); restore-only turns are identical. Requests with images do not take part.

Read ahead: a chat request with `"prefill_only": true` (layer on) reads and saves its prompt without generating and
answers with a short object (`slot_cache.status`: saved / skipped: short / failed: ...; one SSE event if streamed).
Send it with the same tools, stream setting and other fields as the later questions, non-streamed with a long
timeout, and ask the question as a NEW message after it (a question merged into the same message, or a code fence
that switches the layer's route, renders other tokens and is read again). With the cache off it is a no-op.
