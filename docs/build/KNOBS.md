# Launcher settings (environment variables)

A variable stays set in a PowerShell window until you remove it or close the window. At start, the launcher lists
every `BONSAI_*`, `LLAMA_ARG_*` and `GGML_*` variable that is set, and it says when MTP is off and why (issue #7).

| Variable | Default | |
| --- | --- | --- |
| `BONSAI_8GB` | auto (cards with up to 8.5 GB) | 1 = force the 8 GB preset, 0 = turn it off ([8 GB](../8gb/README.md)) |
| `BONSAI_CTX` | 262144 (8 GB: 131072 with less than 24 GB of system RAM or without the MTP head file) | context window |
| `BONSAI_CTK` | q4_0 (12 GB), q3_0 (8 GB) | K/V cache type. q4_0 keeps ~99 % of the 262k window in VRAM on 12 GB; q3_0 is the 8 GB default from bundle-20261015. See [Quality](../quality/README.md#1-kv-cache-precision-measured-changed-the-default) |
| `BONSAI_TIER` | 1 | 0 = all-VRAM cache (then 96k window) |
| `BONSAI_KV_VRAM_CELLS` | auto | pin the VRAM line |
| `BONSAI_VRAM_MARGIN` | 1000 (display on iGPU) / 1300; 8 GB: 225 (400 without drafting) | MiB kept free below the demotion point |
| `BONSAI_SPEC` / `BONSAI_SPEC_DEEP` | 2 / 4 (8 GB: 1 / 1) | draft size, and past the VRAM line |
| `BONSAI_LOOKUP` / `BONSAI_LOOKUP_N` | on / 32 | lookup drafting from the context and its draft limit; `BONSAI_LOOKUP=0` turns it off |
| `BONSAI_DRAFT_WINDOW` | 16384 | rows the draft head keeps |
| `BONSAI_EFFORT` | medium | server default reasoning effort |
| `BONSAI_THINK` | 1 | 0 = thinking off for every request |
| `BONSAI_THINK_BUDGET` | 20480 | thinking tokens before a forced close (-1 unlimited) |
| `BONSAI_HARNESS_PROOF` | 1 | 0 = pass effort words and output caps through unchanged |
| `BONSAI_EFFORT_ALLOWED` | medium | effort words the template sees; others become medium |
| `BONSAI_PORT`, `BONSAI_MODEL` | 8080, auto | |
| `BONSAI_SLOT_SAVE_PATH` | off | a folder for saved conversations (slot files). With the layer on, saving and restoring is automatic for prompts of 16k tokens or more. The files are not removed automatically; at 245k a file is ~3.5 GB at q3_0, ~4.5 GB at q4_0, ~8.5 GB at q8_0. `BONSAI_SLOT_CACHE_*` settings, the slot routes and the measurements: [Saved conversations](../agents-layer/SAVED_CONVERSATIONS.md) |
| `BONSAI_SPILL_GUARD` | 1 | 0 = no spill check. When the card becomes full after the server starts (a browser, a game or a second model takes VRAM, or the NVIDIA driver moves server memory to system RAM: "sysmem fallback"), the server does not stop: it becomes much slower (on an 8 GB card a 200 MiB program took prompt reads from ~400 to 70 tok/s), or a later long prompt fails with "CUDA error: out of memory". The launcher watches the GPU memory counters every 15 s and prints a `spill` line in this window when the server's shared GPU memory grows by more than 256 MiB, or when other programs take GPU memory and the free VRAM gets short (two checks in a row, so about 30 s). It reads the Windows performance counters, so on a Windows in another language it says nothing. To make the server stop instead of running slowly: NVIDIA Control Panel > Manage 3D settings > Program Settings > llama-server.exe > CUDA - Sysmem Fallback Policy > Prefer No Sysmem Fallback |
| `BONSAI_MMPROJ` / `BONSAI_MMPROJ_GPU` | none / 0 | vision projector (`Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` from prism-ml, in `models\`; `LLAMA_ARG_MMPROJ` is picked up too). Default: the image encoder runs on the CPU, no VRAM and no speed cost, ~0.3 s more per image. `BONSAI_MMPROJ_GPU=1`: on the card, and the VRAM line gives up its size (`docs/receipts/vision_probe.log`). A projector the sizing does not know about can over-commit the card and collapse prefill (issue #4, found by @Milor123) |
| `BONSAI_SPARSE` | auto on 8 GB | sparse reads of the system-RAM part of the cache past the VRAM line (8 GB preset): the engine times dense and sparse once per 16k band and keeps the faster. 0 = off, 1 = forced ([8 GB](../8gb/README.md)) |
| `BONSAI_CKPT_EVERY` | 8192 | context checkpoints also every N tokens inside a long message; 0 = only at user messages and prompt ends |
| `BONSAI_RAM_BUDGET` | on | sizes the prompt cache and the checkpoints from the system RAM; 0 = the server defaults |
| `BONSAI_LAYER` | 1 | 0 = no Bonsai layer: the plain server on the port ([the layer](../agents-layer/README.md)) |
| `BONSAI_RS_REPLAY` | 0 | 1 = replay rollback (patch 0070): one recurrent-state plane instead of one per draft token. Needs an engine with patch 0070 (not in a published bundle yet) and drafting on |
