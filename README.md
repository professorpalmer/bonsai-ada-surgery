# Bonsai 2 27B: the full 262k window on 12 GB and 8 GB cards

![Scorecard. RTX 4070 12 GB with q4_0 K/V: 262,144-token window, 260,352 positions in VRAM, decode 96.2 / 76.6 / 60.4 tok/s at 4k / 128k / 245k, a 4k prompt read at 1,294 tok/s, HumanEval 158/164. RTX 2060 SUPER 8 GB with q3_0 K/V: 262,144-token window, 80,640 positions in VRAM, decode 53.4 / 22.3 / 9.8 tok/s, 417 tok/s, HumanEval 163/164](docs/img/scorecard.png)

Ternary Bonsai 2 27B is PrismML's 1.58-bit ternary model (`PTQ1_0`, 5.9 GB). This repo serves it with the full
262,144-token window on 12 GB and 8 GB NVIDIA cards. It has a patched [PrismML llama.cpp](https://github.com/PrismML-Eng/llama.cpp),
a launcher that sizes the K/V cache for the card (q4_0 on 12 GB, q3_0 on 8 GB), MTP drafting, and an optional layer
for agents. The weights are not changed.

## Quick start (Windows, NVIDIA)

1. Download `bonsai-bundle-win-x64.zip` from [Releases](https://github.com/professorpalmer/bonsai-ada-surgery/releases) and unzip it into this repo.
2. Put `Ternary-Bonsai-2-27B-PTQ1_0.gguf` and the MTP head file in `models\` ([details](docs/build/README.md#quick-start-windows-nvidia)).
3. Run `.\start-server.ps1`. The OpenAI-compatible API is on `http://<host>:8080/v1`.

Hugging Face, Linux and builds from source: [docs/build](docs/build/README.md).

## Index

| Directory | What |
| --- | --- |
| [docs/12gb](docs/12gb/README.md) | 12 GB cards: setup, the q4_0 cache, decode and prefill by depth |
| [docs/8gb](docs/8gb/README.md) | 8 GB cards: setup, the q3_0 cache, choosing the window, numbers |
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
