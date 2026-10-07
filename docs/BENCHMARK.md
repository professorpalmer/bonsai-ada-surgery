# Benchmark your own model the way this repo does

This page lets anyone run the quality benchmarks behind this repo's numbers against **any model on any
OpenAI-compatible server**, with the same prompts, chat template, sampling and grading, so the results line up with
ours. The typical use: the same base model at a conventional quantization (for example Qwen3.8-27B at Q4_K_M)
against Bonsai 2 27B, on whatever GPU you have.

Quality at greedy or fixed-seed sampling does not depend on the GPU: the model gives the same answers on a Tesla
P40 and on an RTX 4070, up to rare numeric ties. Speed does depend on it, and speed is not what these runs measure.

## What can be reproduced from this page

| benchmark | runner | runs anywhere? | Bonsai 2 27B, this repo (raw / behind the layer) |
| --- | --- | --- | --- |
| HumanEval 164, tests executed, medium reasoning | `bench/humaneval_run.py --arm medium` | yes | 159 / 160 (HE1) |
| HumanEval 164, thinking off | `bench/humaneval_run.py --arm off` | yes | run it on both models, we will pair it |
| Long exact-work suite, 37 tasks, frozen seeds, raw vs layer | `suite/run_suite.py` | yes (needs the sandbox runtime) | 17 / 28 (S1); 17 / 29 on the second seed set (S2) |
| Tool-call format: native XML + server grammar vs JSON in content | `bench/toolcall_stress.py` | yes (needs a Qwen3-Coder-style template) | 9 of 9 vs 1 of 9 parsed |
| AIME 2025, MMLU-Pro sample, AppWorld | `research/quality-20260929/bench/` | **not yet**: the runners hard-code this machine's ports and paths; the plans and logs are there to read | 52/56 of 60, 71/76 of 100, 70.8% of 168 |

Every number in the right column has a plan written before the result and a receipt: `README.md` (the layer table),
`suite/README.md` (both scoreboards) and `research/quality-20260929/REPORT.md` (rounds HE1, S1, S2).

## 1. Setup (once)

```bash
git clone https://github.com/professorpalmer/bonsai-ada-surgery && cd bonsai-ada-surgery
python3 -m pip install wasmtime                     # Python 3.10 or newer
bash layer/fetch_runtime.sh                          # Linux/macOS; on Windows: layer\fetch_runtime.ps1
```

`fetch_runtime` downloads the sandbox (CPython 3.12 compiled to WebAssembly, checksum verified) and runs 14 isolation
canaries; all must pass. The suite runs every piece of model-written code inside that sandbox: no host files, no
network, no processes, memory and time capped.

HumanEval data: download `HumanEval.jsonl.gz` from
[openai/human-eval](https://github.com/openai/human-eval/tree/master/data) and pass its path with `--problems`.
**HumanEval executes the model's code on your machine** in a short-lived subprocess with a timeout, as the upstream
harness does. Run it in a VM or container if that matters to you.

API key: the runners read a key file. Make one and give the server the same value:

```bash
mkdir -p artifacts && python3 -c "import secrets; print(secrets.token_hex(24))" > artifacts/api_key.txt
```

## 2. Serve the model you want to measure

Any llama.cpp build that loads the model works. Use **this repo's chat template** for every model you compare
(`templates/bonsai-template.jinja`: Qwen3.5/3.8 format, the `reasoning_effort` switch, native tool calls); it is the
template every number above was measured with, so prompts are identical token for token across models.

```bash
llama-server -m Qwen3.8-27B-Q4_K_M.gguf -ngl 99 -fa on -c 65536 -np 1 -ctk q8_0 -ctv q8_0 \
  --jinja --chat-template-file templates/bonsai-template.jinja \
  --chat-template-kwargs '{"reasoning_effort":"medium"}' \
  --reasoning-budget 20480 --reasoning-budget-message "Now produce the complete answer." \
  --temp 1.0 --top-p 0.95 --top-k 20 \
  --host 127.0.0.1 --port 18080 --api-key "$(cat artifacts/api_key.txt)" --alias test-model
```

- `-c 65536`: the suite's longest tasks need ~40k tokens of context. On a 24 GB card with a 27B Q4_K_M (~16.5 GB)
  this fits at q8_0 K/V; lower it to 49152 if it does not.
- `--reasoning-budget 20480` with the message: our raw numbers were measured with this forced close. Leave it on
  for a like-for-like comparison. Both flags exist in upstream llama.cpp and in PrismML's fork.
- The runners send their own sampling per request (see below); the server values are only the fallback.
- **Pascal cards (Tesla P40, GTX 10-series):** use a **CUDA 12** build of llama.cpp. CUDA 13 dropped Pascal, and
  this repo's Windows bundle only carries RTX 20 and newer code, so it will not run there. Expect ~10-15 tok/s for a
  27B at Q4_K_M on a P40; quality is unaffected.
- Bonsai itself needs [PrismML's fork](https://github.com/PrismML-Eng/llama.cpp) (stock llama.cpp cannot load
  `PTQ1_0`). You do not need to rerun Bonsai: its numbers are in the table. Run it too if your hardware allows, and
  the pairing gets tighter.

**The layer arm (optional).** The layer is a Python proxy that works in front of any OpenAI-compatible server:

```bash
BONSAI_LAYER_KEY="$(cat artifacts/api_key.txt)" python3 layer/bonsai_layer.py \
  --host 127.0.0.1 --port 8080 --upstream http://127.0.0.1:18080
```

Now `:18080` is the raw model and `:8080` is the same model behind the layer.

## 3. Run

HumanEval, both arms (greedy, temperature 0; medium allows up to 20,480 output tokens):

```bash
python3 bench/humaneval_run.py --base http://127.0.0.1:18080 --problems HumanEval.jsonl.gz --arm off    --out results/he_off
python3 bench/humaneval_run.py --base http://127.0.0.1:18080 --problems HumanEval.jsonl.gz --arm medium --out results/he_medium
```

The long exact-work suite, raw and behind the layer, paired request by request (frozen plan, fixed seeds; sampling
per request: temperature 1.0, top-p 0.95, top-k 20, min-p 0.05, medium effort):

```bash
python3 suite/run_suite.py --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 \
  --model test-model --out results/suite --label-a raw --label-b layer
```

Without the layer, drop `--base-b`. `--limit 1` runs one item per family as a smoke test (a few minutes) and is
worth doing first.

Tool-call format (optional; measures the server's tool-call parsing with this template more than the model):

```bash
python3 bench/toolcall_stress.py --base http://127.0.0.1:18080 --key "$(cat artifacts/api_key.txt)" --n 3 --out results/toolcall_stress.json
```

**Time, roughly,** at decode speed S tok/s: HumanEval off ~40k output tokens; HumanEval medium ~1M; the suite raw arm
~0.5-0.8M and the layer arm about two thirds of that. On a P40 at ~12 tok/s: HumanEval off about an hour, the suite
raw arm about half a day, HumanEval medium about a day.

## 4. What to send back

Open an issue or a pull request with:

- the `summary.json` of each HumanEval arm and the `results/suite` folder (`results.jsonl` and the scoreboard the
  runner prints at the end);
- the exact `llama-server` command line, the llama.cpp commit (`llama-server --version`), the GPU;
- the model file's name and SHA-256 (`sha256sum model.gguf`), so the result is tied to exact weights.

We pair your numbers with ours item by item and publish them with credit to you.
