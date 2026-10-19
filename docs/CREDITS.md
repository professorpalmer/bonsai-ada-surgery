# Credits

PrismML for the model and the fork. sudoingX for the planar-transposed layout, the batch-invariant mode, the
Hadamard-inverse fix and the MTP graft tools. ProCreations for the on-policy MTP head (Apache 2.0; independent
of PrismML). Killy (@net_termina) for the failure census and the HumanEval plates that turned "quality is worse"
into fixable buckets. Dogukan for the PatchEval agent traces and the loop finding on the Bonsai 2 small models
(`docs/research/small-models-20261006/`). MIT for everything here; weights are PrismML's (Apache 2.0). Not affiliated with PrismML.

## Hopper/Blackwell PDL fix

Patch `0026` carries `09b6cce`. The planar PTQ1_0 mat-vec calls `ggml_cuda_pdl_sync()` before reading activations
produced by the q8_1 quantization kernel. Without that wait, programmatic dependent launch can let the consumer
read unfinished output on Hopper/Blackwell. LamplighterPaul reported corrupt `llama-server` output on an RTX 5080,
including the `GGML_CUDA_PDL=0` isolation, in
[Prism #218](https://github.com/PrismML-Eng/llama.cpp/pull/218#issuecomment-5833071266). This is a synchronization
bug, separate from KV-cache quantization quality. The helper is a no-op on Ampere/Ada. Windows Release bundles from
2026-09-27 on contain it; older downloaded binaries are not updated by pulling patches. The reporter's hardware
result is not a new hardware test of this bundle.

The [PDL code-generation check](https://github.com/professorpalmer/bonsai-ada-surgery/actions/workflows/pdl-codegen.yml)
compiles the actual planar kernel for sm_89, sm_90, and sm_120a. It checks all 24 column/fusion template variants.
On Hopper/Blackwell, removing the fix must fail the ordering check; with the fix, one unconditional
`griddepcontrol.wait` must precede global-memory loads. Ada must emit no wait in either case. This is a compiler
regression check, not a GPU runtime or performance benchmark. To reproduce with CUDA 13 and an already-patched
source checkout:

```bash
python3 tests/check_pdl_codegen.py /path/to/patched/llama.cpp --arch 120a
```
