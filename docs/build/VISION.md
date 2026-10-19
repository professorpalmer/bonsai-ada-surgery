# Vision (images)

The model reads images when the launcher loads PrismML's vision projector. It is **off by default**: without the
projector the server has no image input, and it rejects a request that contains an image.

1. Download `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` (600 MiB) from
   [prism-ml/Ternary-Bonsai-2-27B-gguf](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) into `models\`.
2. Start the launcher with it:

   ```powershell
   $env:BONSAI_MMPROJ = 'Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf'
   .\start-server.ps1
   ```

   The launcher prints a `vision` line. Send images as OpenAI `image_url` content parts with a base64 data URL (the tested form).

- **Default: the image encoder runs on the CPU.** It uses no VRAM and does not change text speed; a small test image
  took 1.3 s (`docs/receipts/vision_probe.log`). This is the right setting for 8 GB cards.
- **`BONSAI_MMPROJ_GPU=1`** puts the encoder on the card (1.0 s for the same image). The launcher then gives up the
  projector's size from the VRAM line, so fewer positions fit in VRAM.
- The Q8_0 projector is the tested one. `LLAMA_ARG_MMPROJ` works too.
- Image requests pass through the layer on `:8080` unchanged (tested 2026-10-14: 1.6 s, a correct answer;
  `docs/receipts/vision_layer.log`). **Without the projector** the server answers at once with HTTP 500
  `image input is not supported - hint: ... you may need to provide the mmproj`: that error means `BONSAI_MMPROJ` is
  not set.
