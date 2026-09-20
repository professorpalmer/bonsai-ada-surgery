# Bonsai 2 27B quality: what the runtime controls, measured

**262,144 tokens is the trained maximum.** The bundle serves that window. Default on a 12 GB
card is 98,304 with q8_0 K/V (10.8 GB, no paging). The same 12 GB card takes the full 262k at
q4_0 with the draft head off; 16 GB and up take 262k at q8_0. Recipes and VRAM are in the
memory table below and in the README headline.

Kernel work made this model fast on a 12 GB card. This page is about the other complaint people
have, that Bonsai 2 is worse than its 98% retention claim on code and agentic work, and about which
part of that gap is *serving software* rather than compression. Every number here is measured on
the original PrismML `Ternary-Bonsai-2-27B-PTQ1_0.gguf` with the binaries in this repo on an RTX
4070 12 GB. The recipe changes that come out of it are the defaults of `start-server.ps1`.

Nothing here touches the weights. Same 1.75 bits per weight, same file.

## The frame: Killy's failure census

[@net_termina](https://x.com/net_termina) ran 34 adversarial agentic tasks against Bonsai 2 and the
real Qwen3.8-27B teacher (teacher 25 correct, Bonsai 15) and classified all 19 Bonsai failures:

| Failures | Cause | Nature |
| ---: | --- | --- |
| 7 | tool-call JSON the harness could not parse: an escape dropped 4k-12k characters into a code string | serving format |
| 8 | ran out of steps | mostly serving: runaway thinking, retry loops after a bad call |
| 4 | understood the task, got it wrong | compression |

His reasoning benchmarks survived compression almost untouched (GSM8K 480 vs 480, passkey 40/40,
MATH-500 452 vs 461) because reasoning is redundant and self-correcting. Exact syntax is not: one
wrong token deep inside a string kills a call and nothing repairs it. That points the runtime at two
things: emit fewer wrong tokens (KV precision), and never let a wrong token become an unparseable
call (format + grammar).

One caveat he also established and that applies to every number below: the "F16" GGUF in
PrismML's repo is the ternary weights re-expanded to 16 bit (every 128-weight group holds one
magnitude, exactly 42 of 128 are zero, embeddings and `lm_head` included). KL against it is KL of
the model against itself. So this page only measures the model against *itself under different
runtime settings*. Absolute distance to the teacher needs the real Qwen3.8-27B weights.

## 1. KV cache precision (measured, changed the default)

Every published 12 GB recipe for this model, ours included until now, runs `-ctk q4_0 -ctv q4_0` to
fit the full 262,144-token window. Nobody had measured what that costs on this model.

Method: `llama-perplexity` KL divergence, wikitext-2 test set, 16,384-token chunks x 4 (65k tokens
processed, the second half of each chunk scored, so every scored token sits at 8k-16k depth). The
reference is the same model with f16 K/V; each quantized cache is scored token-by-token against it.
`bench/kv_kl_sweep.ps1` reproduces it (base run 1.5 min, each q8_0/q4_0 config 1.5 min; the mixed
config takes 44 min because mixed K/V types are not on the CUDA flash-attention path and fall back
to the CPU).

| K / V cache | Mean KL vs f16 KV | Top-1 token agrees with f16 KV | Max KL on one token | PPL vs f16 KV |
| --- | ---: | ---: | ---: | ---: |
| q8_0 / q8_0 | 0.00017 | 99.38% | 0.18 | -0.03% |
| q8_0 K / q4_0 V | 0.00094 | 98.59% | 3.22 | -0.06% |
| q4_0 / q4_0 | 0.00218 | 97.93% | 0.94 | +0.18% |

Reading it:

- Perplexity does not see the difference (+0.18%), which is why the q4_0 recipe spread without
  anyone flagging it. The argmax does: **q4_0 flips the top token on 1 in 48 positions at depth,
  q8_0 on 1 in 160.** Twelve times the divergence. For prose that is a synonym; for code, an escape
  sequence, a closing quote or a JSON key it is the failure Killy counted. It also compounds: a
  long agentic session re-reads its own earlier output through the same cache on every turn.
- K precision is a bit more than half the damage, but V at 4 bits still costs 5x q8_0 and produced
  the single worst token in the set (KL 3.2, an 83-point probability swing). Mixed K/V is not a
  shortcut, and today it is also 10x slower on CUDA.

Memory. Bonsai 2 has 16 full-attention layers (every 4th of 64), 4 KV heads x 256 dims, so K+V is
32,768 values per token:

| Window | q4_0 KV | q8_0 KV | VRAM in use with the 6.3 GB MTP file and its draft context (measured) |
| ---: | ---: | ---: | --- |
| 65,536 | 1.2 GB | 2.3 GB | q8_0: 9.6 GB |
| 98,304 | 1.8 GB | 3.4 GB | q8_0: 10.8 GB |
| 131,072 | 2.4 GB | 4.6 GB | q4_0: 9.9 GB; q8_0: 11.96 GB, **pages** |
| 262,144 | 4.8 GB | 9.1 GB | q4_0: 11.96 GB, **pages**; q8_0 needs 16 GB |

"Pages" is the finding that moved the default. `128k/q8_0 + draft` allocates without complaint
on a 12 GB card, and a fresh-context probe runs at full speed, but at 11.96 GB Windows (WDDM)
has begun paging the cache to system memory: decode at 32k depth measured 30.1 tok/s against
47.3 with the same setup in a 64k window, and 12.6 tok/s at 100k. PrismML's own build at
11.35 GB did not page. The line is somewhere between 11.4 and 11.9 GB in use, and a recipe has
to stay under it at *every* depth, not just on the probe that gets screenshotted.

**Default: 98,304 tokens with q8_0 K/V, 10.8 GB in use, no paging at any depth.** On 12 GB:
`BONSAI_CTX=131072 BONSAI_CTK=q4_0` for a longer window with the q4_0 noise;
`BONSAI_CTX=262144 BONSAI_CTK=q4_0 BONSAI_SPEC=0` for the full window (the draft context is what
pushes 262k over the line). 16 GB and up: 262k with q8_0.

Not yet done: `iq4_nl` K/V. Same 4.5 bits per value as q4_0 with a non-linear codebook, usually a
large KL improvement at identical memory. It is not implemented in the CUDA flash-attention kernels
(the in-place q4_0/q8_0 MMA path in this repo would need an iq4_nl variant), so it has to be
measured through the slow CPU fallback first. If it recovers most of the q4_0 gap it becomes the
free 262k answer on 12 GB.

## 2. Runaway thinking (reproduced, changed the default)

The chat template defaults `reasoning_effort` to `xhigh`. With tools attached, `reasoning_effort=low`
and a 9,000-token budget, the first stress request ("write a 250-line Python module via
`write_file`") spent all 9,000 tokens inside `<think>` and never emitted the call
(`finish_reason: length`). That is one of Killy's 8 "ran out of steps" in a single request, at
~60 tok/s for 2.5 minutes.

`start-server.ps1` now passes `--reasoning-budget 4096` (`BONSAI_THINK_BUDGET`, -1 to lift the cap)
and `--chat-template-kwargs {"reasoning_effort":"low"}` (`BONSAI_EFFORT`). Per-request
`chat_template_kwargs` still override the effort; the budget is a hard stop that closes the think
block and lets the answer start.

Measured with the cap in place and thinking on: on all three tool-call stress tasks the model used
the full 4,096 tokens before starting its call (about 15k characters of reasoning about a
250-line file), and two of the three then ran into the 9,000-token test cap before finishing the
payload. With thinking off, 9 of 9 calls arrived (next section). So for agent harnesses the right
setting is **`BONSAI_THINK=0`**, which sets `enable_thinking=false` for every request unless the
request says otherwise; the budget stays as the safety net for chat use. Two costs to know: the
budget is a host-side sampler, and llama.cpp disables GPU-side sampling when one is set, which is
4% decode on this card (96.8 vs 100.7 tok/s); `BONSAI_THINK_BUDGET=-1` gets it back.

## 3. Tool-call syntax (measured: format and grammar, not the model)

Bonsai 2's native tool-call format is Qwen3-Coder XML, not JSON:

```
<tool_call>
<function=write_file>
<parameter=path>
parser.py
</parameter>
<parameter=content>
...raw file content, no escaping...
</parameter>
</function>
</tool_call>
```

String parameters are raw text terminated by `</parameter>`; there is no escaping to get wrong.
The `llama-server` in this bundle parses that format with a PEG parser and, when a request carries
`tools`, arms a lazy grammar (`common_chat_params_init_qwen3_coder`): string parameters accept
anything up to the closing tag, object/array parameters are JSON-schema-constrained, so an
unescaped quote inside a JSON value is simply not a legal next token. Under this path the model
cannot produce a call the server fails to parse. The failure Killy measured needs a harness that
makes the model write Hermes-style `{"name":..., "arguments":{...}}` with the code escaped inside a
JSON string.

`bench/toolcall_stress.py` reproduces both paths against this server with payload-heavy tasks
(250-line modules full of quotes, backslashes, regexes and f-strings; three multi-line edits as a
JSON array parameter), thinking off, sampling at the recommended `temp 1.0 / top-p 0.95 / top-k 20`:

| Arm | Format | Calls parsed | Finished within 9,000 tokens | Payload compiles as Python | Median payload | Decode |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| A | native XML + server grammar (`tools` in request) | **9 / 9** | 9 / 9 | 3 / 9 (see below) | 22,551 chars | 66.9 tok/s |
| B | Hermes JSON in content, no grammar | **1 / 9** | 5 / 9 | 0 / 9 | 14,543 chars | 77.5 tok/s |

Three runs x three tasks per arm (`artifacts/eval/toolcall_stress.json`). Every JSON-arm failure
was Killy's: the object closes one bracket short at the very end of a 3k-23k character payload
(`Expecting ',' delimiter at char 23319 of 23319`), or a string is never terminated
(`Unterminated string starting at char 74`), or the model never gets out of the payload at all
(4 of 9 hit the 9,000-token cap). None of those can happen on the grammar path, and none did.

"Payload compiles" is a stricter bar than "call parsed" and mostly measures the model, not the
call. The six grammar-arm misses break down as: two `apply_edits` tasks where the model called
`write_file` first to create the file it was asked to edit (a legitimate plan; the calls were
well-formed), and four `write_file` payloads with a real Python bug inside the 250-line module:
a `"""` opened inside a `"""` docstring, a bare `'` inside a `'...'` raw regex, a `C:\Users` path
in a non-raw string. Those errors exist in either format, reach the file intact, and an agent loop
sees them as an ordinary Python error on the next step and can fix them. An unparseable call is
different: it ends the step with nothing to repair. That is the column that matters, and it went
from 8 of 9 failing to 0 of 9.

Serving advice that falls out of this, for any harness in front of this server: send `tools` and
let the server format and parse the call. Do not prompt the model to write JSON tool calls in
content, and do not run it behind a server that lacks the Qwen3-Coder XML grammar.

Cost: grammar-constrained sampling runs on the host, so decode with `tools` attached is slower
than plain decode: 66.9 vs 77.5 tok/s above, about 14%, paid only on requests that carry tools.
(Both arms are below the 93 tok/s plain-chat figure because these payloads are long code with
speculative acceptance around 0.65 rather than the short-answer probe.)

## 4. Speed at depth, and where the draft head stops paying (measured, changed the default)

Every speed claim for this model, this repo's earlier ones included, is a fresh-context probe.
Agentic sessions live at 20k-80k tokens. `bench/served_depth.ps1` runs the same three prompts
behind 32k and 64k tokens of varied filler (sized with the server's tokenizer, not guessed) and
reads the server's own timings. RTX 4070, 96k window, q8_0 K/V, 400-token answers:

| decode tok/s | fresh | 32k deep | 64k deep |
| --- | ---: | ---: | ---: |
| PrismML build | 54.0 | 40.7 | 31.9 |
| bundle kernels, no draft | 68.3 | 49.1 | (38 est.) |
| bundle + MTP draft, always on | 101.2 | 45.3 | 27.2 |
| bundle + MTP draft to 24k, then plain (**default**) | 100.7 | 47.6 | 36.9 |

The draft head is +85% on a fresh context and a net loss past ~28k tokens. Deep in the context a
step is bound by reading the KV cache; the two draft passes (the MTP layer has its own attention
over the whole context) and the 3-column verify read more of it without shortening the step, and
acceptance does not rise to compensate. Rather than pick between fresh speed and deep speed, the
bundle adds `--spec-draft-depth-max` to `llama-server` (patch 0020): the slot drafts while the
sequence is shorter than N and decodes one token per step after, skipping the draft-context
catch-up too. The recipe sets 24,576.

At 64k the bundle's lead shrinks to 16% because attention dominates and the flash-attention
kernel is shared with PrismML's build. That kernel at depth, with q8_0 K/V and head size 256, is
the next thing to open up; nothing in this bundle touches it beyond the in-place K/V read.

## What was not found

- No evidence of a numerics problem in the CUDA path that would degrade the model relative to
  CPU reference: every kernel in the bundle is checked against the CPU implementation
  (`test-backend-ops`, all PTQ1_0 shapes), greedy output is byte-identical with each optimization
  on and off, and the speculative draft is byte-identical to non-speculative decoding under
  `GGML_CUDA_BATCH_INVARIANT=1`.
- Nothing here changes the 4-of-19 "understood the task, got it wrong" bucket. That is the
  compression, and the only lever on it is training against the real teacher, which is out of
  scope for a runtime.

## Reproduce

```powershell
# KV precision (needs artifacts\eval\wiki.test.raw: wikitext-2-raw-v1 from huggingface.co/datasets/ggml-org/ci)
bench\kv_kl_sweep.ps1 -Model models\Ternary-Bonsai-2-27B-PTQ1_0.gguf -Bin bin -Configs q8_0:q8_0,q4_0:q4_0

# tool-call syntax, against a running start-server.ps1 (port 8080 by default)
python bench\toolcall_stress.py --base http://127.0.0.1:8080 --key (Get-Content artifacts\api_key.txt -Raw).Trim() --n 3
```
