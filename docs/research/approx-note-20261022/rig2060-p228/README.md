# P228: post-zip check of bundle-20261022 on the RTX 2060 SUPER (#233)

The approximate-length note, as the layer of the shipped zip adds it, on the published model file.

- **Zip:** bundle-20261022, SHA-256 `19dd04ed...` (equal to the GitHub digest). No engine change: the bundle-20261021 bins.
- **Model:** the Hugging Face `Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf` @ `70ed43ce`, made into its Q4_0 head file. `/props` gives `chat_template` 9,311 chars, with `operating_rules`.
- **Launcher:** `BONSAI_8GB=1` + `BONSAI_MODEL`. Layer on at :8080, llama-server at :18080. Line 87,552, stock clocks.
- **Requests:** plain, with no note in the text, sent to the layer (`p228_layer.py`, a copy of `apc_ab.py` with arm L). Seeds 8 and 9, the 7 note prompts: 14 requests, 22:17-22:43 CDT 2026-10-22.

Gates (declared before the run in `jobrun_p228.sh` and on #233; L1 changed before any result, #233 comment 6356556420):

| gate | condition | result |
|---|---|---|
| L1 | 14 `approximate-length note on 1 writing request(s)` lines in `layer.log` | **14 / 14: PASS** |
| L2 | total wall at most 0.7x P227 M on the same cells (4,444.5 s) | 1,567.5 s = **0.353x: PASS** (0.864x of P227 A2) |
| L3 | median numbered words at most 10; 0 budget closes | median **0**; **0** closes: **PASS** |
| L4 | 0 empty, `write_file` 8 / 8, 0 cut at the cap, 0 count leaks, 0 false save claims, 0 CUDA errors | 0 / 8 of 8 / 0 / 0 / 0 / 0 (0 spill lines): **PASS** |

- **Length:** median words / asked 1.10, max 1.49.
- **Seed 8 matches P227 A2:** the 7 cells have the same thinking-word counts as P227's A2, where the note was added by hand. So the layer adds exactly the tested text.
- **`approx_notes`:** the response field is absent on this forward path (`None` in `runs.jsonl`), the known gap that #238 fixes.
