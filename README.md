# Bonsai 2 27B: the full 262k window on 12 GB and 8 GB cards

![Scorecard. RTX 4070 12 GB with q4_0 K/V: 262,144-token window, 260,352 positions in VRAM, decode 96.5 / 72.0 / 60.4 tok/s at 4k / 128k / 245k, a 4k prompt read at 1,297 tok/s, HumanEval 158/164. RTX 2060 SUPER 8 GB with q3_0 K/V: 262,144-token window, 92,160 positions in VRAM, decode 52.4 / 29.6 / 11.4 tok/s, 417 tok/s, HumanEval 163/164](docs/img/scorecard.png)

Ternary Bonsai 2 27B is PrismML's 1.58-bit ternary model (`PTQ1_0`, 5.9 GB). This repo serves it with the full
262,144-token window on 12 GB and 8 GB NVIDIA cards. It has a patched [PrismML llama.cpp](https://github.com/PrismML-Eng/llama.cpp),
a launcher that sizes the K/V cache for the card (q4_0 on 12 GB, q3_0 on 8 GB), MTP drafting, and an optional layer
for agents. The weights are not changed.

![Quality on the same weights, before and after the runtime fixes. Apps that send effort "high": HTTP 500 (0 of 20 answered) to HumanEval 160/164. Apps with a 4096-token cap: 148 to 157/164. SVG drawings with the template default xhigh: 0/4 (4 empty) to 4/4 at medium. Tool calls parsed: 1/9 (JSON in content) to 9/9 (native XML and a grammar). AIME 2025: 52 to 56 of 60 with the layer. Voxel pagoda page: 3/6 first try to 6/6 after render and repair](docs/img/fixed.png)

Most of the code and agent losses people report on this model come from the runtime, not from the compression. With
the same weights, the server fixes them: effort words that the template rejects, output caps that end the thinking,
the `xhigh` template default (runaway thinking), and tool calls in JSON. Details: [docs/quality](docs/quality/README.md).

## Quick start (Windows, NVIDIA)

1. Download `bonsai-bundle-win-x64.zip` from [Releases](https://github.com/professorpalmer/bonsai-ada-surgery/releases) and unzip it into this repo.
2. Put `Ternary-Bonsai-2-27B-PTQ1_0.gguf` and the MTP head file in `models\` ([details](docs/build/README.md#quick-start-windows-nvidia)).
3. Run `.\start-server.ps1`. The OpenAI-compatible API is on `http://<host>:8080/v1`.

Hugging Face, Linux and builds from source: [docs/build](docs/build/README.md).

## Index

| Directory | What |
| --- | --- |
| [docs/12gb](docs/12gb/README.md) | 12 GB cards: setup, the q4_0 cache, decode and prefill by depth |
| [docs/8gb](docs/8gb/README.md) | 8 GB cards: setup, the q3_0 cache, choosing the window, numbers, [two weeks on 8 GB](docs/8gb/README.md#two-weeks-on-8-gb-2026-10-06-to-2026-10-20) |
| [docs/quality](docs/quality/README.md) | KV precision, reasoning effort, tool calls, HumanEval; benchmark your own model |
| [docs/agents-layer](docs/agents-layer/README.md) | the Bonsai layer (API cards, sandboxed Python), agent use, saved conversations |
| [docs/build](docs/build/README.md) | install, Linux, build from source, launcher settings, vision, the patch stack, upgrading |
| [docs/speed](docs/speed/README.md) | decode and prefill past the VRAM line, ideas tested and not adopted |
| [docs/receipts](docs/receipts/README.md) | raw logs behind the numbers; measure it yourself |
| [docs/research](docs/research/) | every study with its plan, gates and records |
| [docs/cards](docs/cards/README.md) | the card sources: each card keeps its numbers in one place |

## Credits

Credits and thanks: [docs/CREDITS.md](docs/CREDITS.md). MIT for everything here; weights are PrismML's (Apache 2.0).
Not affiliated with PrismML.
