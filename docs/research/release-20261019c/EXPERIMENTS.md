# Results

2026-10-19 23:35-23:39, RTX 4070 12 GB. Receipts: `release_1019c.log`; scripts `rel1019c.sh`, `r3_image.py`,
`make_bundle_1019c.py`. Zip sha256 `e84d8c6d21deaea1...`, made from the release branch at `2643bedf` (the cards rendered
just before).

| Gate | Result |
|---|---|
| R1 zip | PASS: outside `docs/` no new or removed entries, every `bin/` file identical to 1019b (engine `810d93e5aa`), changed `README.md`, `layer/bonsai_layer.py`, `start-server.ps1`; 0 control-byte files; 0 broken relative links |
| R2 launcher | PASS: `BONSAI_8GB=1` `draft 1 (2 past the VRAM line)`, `pending inputs of 2 tokens`; `BONSAI_RS_REPLAY=0` `draft 1 (1 past ...)`, no replay line; default `draft 2 (4 past ...)`, no replay line; three greedy answers, 0 CUDA errors |
| R3 images without mmproj | PASS: through the layer 200 with text ("I can't view the image directly ... Could you describe it in text?"), `images_removed` 1; straight to llama-server 500 ("image input is not supported"); 0 CUDA errors |
| R4 saved conversations | PASS: 3 turns (slot files 1, 2, 3); A2 / B2 read 25 / 24 new tokens after their own saves; 0 CUDA errors |

Cards checked as images (the 8 GB decode line 52.4 / 39.9 / 29.6 / 18.6 / 11.4, the 8 GB VRAM line 92,160).
Verdict: publish bundle-20261019c as the latest release.
