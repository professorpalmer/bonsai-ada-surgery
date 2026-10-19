# Empty replies cut at max_tokens (layer fix, 2026-10-19)

Symptom: through the layer, a reply that max_tokens cuts can come back with empty content, while the server without
the layer returns the cut text.

Cause: the layer offers its run_python tool. On a request such as "write a report on this document" the model can
start a run_python call and write the report into a Python string. When max_tokens cuts that call, the layer
(correctly) neither runs nor shows the half-written call, so it dropped it and handed back content "" and no calls.

Fix: when a round is cut inside the layer's own tool call and holds no text, the layer asks once more with the same
messages and without its tool (streamed and non-streamed). Cost: such a reply spends up to twice max_tokens of
generation (the cut round is lost); `layer.cut_retry` marks it in non-streamed replies.

Checks:
- Offline `tests/test_cut_retry.py`: fails on the old layer (content "", tool_calls []), passes on the fix (one retry,
  no half-written call reaches the client, a normal answer makes one call). The other layer suites pass.
- Live (`live.jsonl`; bundle-20261018f, 8 GB preset, layer on, thinking off; max_tokens 40 / 250 at 0, 4k and 64k,
  stream off and on): old layer 2 of 6 with text (both 4k and 64k document requests empty, stream off and on); fixed
  layer 6 of 6 with text (1,018-1,177 characters); the short question is answered directly in both (no retry);
  0 CUDA errors.
