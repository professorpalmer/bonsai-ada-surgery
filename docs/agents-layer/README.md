# The Bonsai layer and agent use

![Agent work on both cards. RTX 4070 12 GB: tool calls parsed 9 of 9, effort "high" requests 0 to 160 of 164 on HumanEval, AppWorld 70.8 %, a 64k edited prompt 64.5 to 15.5 s, file rewrites 117 to 352 tok/s. RTX 2060 SUPER 8 GB: a 64k edited prompt 272-294 to 18-58 s, file rewrites 58.2 to 125.9 tok/s; AppWorld and the effort replay not measured on 8 GB](img/agentic.png)

This page has three parts:

- [The layer](#the-layer): API cards, the API check, the sandboxed Python tool, the key check.
- [For agents and apps](#for-agents-and-apps): what to send.
- [Saved conversations](SAVED_CONVERSATIONS.md): long conversations saved to disk and restored in seconds.

## The layer

A small server-side layer that `start-server.ps1` puts in front of `llama-server` on the same port, so clients
change nothing. It does four things:

- **API cards.** For Python coding requests it appends the exact API of the modules involved (generated from a
  real Python 3.12 runtime) to the first user message, with one sentence asking the model to use the library.
- **API check.** It checks code the model wrote in earlier tool calls for names and keyword arguments that do not
  exist, and notes them on the tool result.
- **Sandboxed Python tool.** For requests that bring no tools of their own, streamed or not, the model gets a
  `run_python` tool that runs in CPython on WASI (no host files, network or processes). The user's message text is
  available to the program as `input.txt`, so the model does not retype data. In a stream, the tool rounds appear
  as short notes in the reasoning stream; the answer streams as usual. Requests with client tools are passed
  through untouched (the model otherwise retypes paginated tool data into code and loses tasks).
  Writing requests (the first user message asks for a story, poem, chapter, essay, article, letter and similar,
  not for code) do not get the tool: offered it, the model counted the words of its text in the sandbox, up to 5
  rounds, and a 1,500-word story took 341 s instead of 61 s, with no quality gain
  ([story-think-20261021](../research/story-think-20261021/README.md)). `"code_interpreter": true` still offers it.
  A writing request that names a length ("a 1,500-word story", 200-10,000 words or tokens, no hard limit) also
  gets one sentence at its end: the length is approximate, and the model must not count the words one by one.
  Without it the model counted each word of its draft in its thinking: with it, writing requests took 0.48x the time,
  with the same quality in blind judging ([approx-note-20261022](../research/approx-note-20261022/README.md)).
  `BONSAI_APPROX_NOTE=0` or `"approx_note": false` turns it off.
- **Key check.** Requests with a wrong API key are rejected before any work is done.

Enable it once with `layer\fetch_runtime.ps1` (downloads the checksummed WASI Python, installs `wasmtime`, runs the
isolation canaries). It needs Python 3 on PATH. Without the runtime the plain server starts as before;
`BONSAI_LAYER=0` turns the layer off. Per request: `"code_interpreter": true|false`, `"api_cards": false`,
`"api_lint": false`, `"input_file": false`.

Measured on one RTX 4070, small paired task sets, plans and gates frozen before results (details and limits in
[docs/research/quality-20260929/REPORT.md](../research/quality-20260929/REPORT.md)). These runs were not repeated on
an 8 GB card:

| | raw server | with the layer |
| --- | ---: | ---: |
| product benchmark, gain tasks, fresh seeds (P2) | 8/20 | **19/20**, 0 losses |
| product benchmark, regression tasks (P2) | 14/17 | 15/17, 0 losses; non-coding requests pass through byte-identical |
| tar+gzip coding task, automatic cards | ~1/30 | 10/14 |
| ZIP coding task, automatic cards (E11, P2) | 0/10 | 8/10 |
| MIME email coding task (E11) | 0/6 | 0/6 (no transfer) |
| data questions, tokens with `input.txt` (E12) | | -58%, same correctness |
| streaming vs non-streaming tool loop (E13) | 12/12 | 12/12 |
| AIME 2025, 30 problems x 2 seeds (A1, A1b) | 52/60 | 56/60 (6 rescues, 2 losses: pre-declared gate not met; 1.17x tokens) |
| HumanEval 164, medium thinking (HE1) | 159/164 | 160/164 (neutral) |
| MATH-500, 100 integer-answer problems (M5) | 99/100 | 100/100 (neutral at a ceiling; 0.83x tokens) |
| MMLU-Pro, 100 questions over 13 subjects (K1) | 71/100 | 76/100 (10 rescues, 5 losses: no harm; 0.80x tokens) |
| AppWorld, 20 tasks, ReAct code agent (AW1, AW1b) | 13/20 | 15/20 after the fix (pure passthrough; 4/20 before it: the layer must not offer its tool to a client that runs code itself) |
| AppWorld, all 168 tasks, ReAct code agent, this serve as shipped (AW2) | 119/168 = **70.8%** (95% CI 63.6-77.2); wrong-format failures 1, step-cap failures 1 | layer not involved (passthrough). Public figure for the larger PQ2_0 file on the stock fork: 64.3% with 16 + 15 such failures |
| AppWorld, all 168 tasks, Prism's stock PQ2_0 (2.13 bpw) on this serve (AW2b) | 114/168 = 67.9% (CI 60.5-74.5); 0 wrong-format, 0 step-cap | same trits as PTQ1_0, same score within noise; public figure for this file on the stock fork: 64.3% |

Cards are proven on two library families and not on a third. Token cost through the layer, P2: long computations
0.08x to 0.76x, coding 0.81x to 0.87x, weblog 1.11x, checklist 1.16x.

## For agents and apps

- Send `tools` and let the server format and parse calls; do not prompt for JSON tool calls in content.
- Tool-heavy agents: `chat_template_kwargs: {"enable_thinking": false}` per request. Chat and coding answers:
  leave the server default (medium).
- Clients that cap `max_tokens` low are fine: with thinking on the server raises the cap (disable with
  `BONSAI_HARNESS_PROOF=0`).
- Keep the tool list the same for the whole session. The chat template puts the tools near the start of the prompt,
  so a tool that is added, removed or described differently (for example an MCP server that stops or starts) makes
  the server read the conversation again from there: 6 minutes for 172k tokens in issue #7. Start the MCP
  servers before the session. The layer writes one line to `logs/layer.log` for each such change, with the names
  of the tools or the number of the message that changed (`BONSAI_LAYER_PREFIX_LOG=0` turns it off).
  With pi and [pi-mcp-adapter](https://github.com/nicobailon/pi-mcp-adapter), a refresh of its direct tools
  ("MCP: direct tools refreshed") changes the system prompt the same way (issue #7: 221,714 tokens read again,
  7 minutes). Set `"settings": {"freezeDirectTools": true}` in `~/.pi/agent/mcp-adapter.json`, and give the tools you
  always use a fixed `"directTools": [...]` list instead of `"search"`.

What the server does for agent work, by card. "Not measured" means that no run on that card is published.

| | RTX 4070 12 GB | RTX 2060 SUPER 8 GB |
| --- | --- | --- |
| a prompt that changes inside one long message (an edited tool result), 64k | 64.5 -> 15.5 s per request (`docs/receipts/ckpt_every_nt_12gb.jsonl`) | 272-294 -> 18-58 s (`docs/receipts/ckpt_every_nt_8gb.jsonl`) |
| file rewrites with lookup drafting, decode | 117 -> 352 tok/s at 4k (`docs/receipts/lookup_ab.jsonl`) | 58.2 -> 125.9 tok/s at depth 0 (`docs/receipts/lookup_ab_8gb.jsonl`) |
| an agent request with 107 tools at 63k | 41.8 -> 61.2 tok/s (`docs/receipts/issue7_fix_ab.log`) | not measured |
| tool calls parsed, native XML + server grammar | 9 of 9 (JSON in content: 1 of 9) | not measured |
| apps that send `effort: "high"`, HumanEval 164 | 0 (HTTP 500) -> 160 | not measured |
| AppWorld, all 168 test tasks | 70.8 % | not measured |

The tool-call and effort details are in [Quality](../quality/README.md).
