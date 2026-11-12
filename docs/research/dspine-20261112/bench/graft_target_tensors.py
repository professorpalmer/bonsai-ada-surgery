"""Copy a draft GGUF and add tensors from another GGUF (raw, same quant type).

Used to give the DSpine draft the full-precision Qwen3.8-27B token embeddings (and output head) instead of the
ternary target's, which the DFlash graph uses when the draft file carries none:
python graft_target_tensors.py draft.gguf donor.gguf out.gguf token_embd.weight [output.weight]
"""
import sys

import gguf
from gguf import GGUFReader, GGUFWriter, GGUFValueType

src, donor, out, *names = sys.argv[1:]
r = GGUFReader(src)
d = GGUFReader(donor)
arch = bytes(r.fields["general.architecture"].parts[-1]).decode()
w = GGUFWriter(out, arch)

for key, f in r.fields.items():
    if key.startswith("GGUF.") or key == "general.architecture":
        continue
    t = f.types[0]
    if t == GGUFValueType.ARRAY:
        sub = f.types[-1]
        if sub == GGUFValueType.STRING:
            val = [bytes(f.parts[i]).decode("utf-8", errors="surrogateescape") for i in f.data]
        else:
            val = [f.parts[i].tolist()[0] for i in f.data]
        w.add_key_value(key, val, t, sub_type=sub)
    elif t == GGUFValueType.STRING:
        w.add_key_value(key, bytes(f.parts[-1]).decode("utf-8", errors="surrogateescape"), t)
    else:
        w.add_key_value(key, f.parts[-1].tolist()[0], t)

def add(t):
    shape = [int(x) for x in reversed(t.shape.tolist())]  # numpy order
    w.add_tensor(t.name, t.data, raw_shape=gguf.quant_shape_to_byte_shape(shape, t.tensor_type) if t.tensor_type not in
                 (gguf.GGMLQuantizationType.F32, gguf.GGMLQuantizationType.F16, gguf.GGMLQuantizationType.BF16) else shape,
                 raw_dtype=t.tensor_type)

for t in r.tensors:
    add(t)
dt = {t.name: t for t in d.tensors}
for n in names:
    add(dt[n])
    print("added", n, dt[n].tensor_type.name)

w.write_header_to_file()
w.write_kv_data_to_file()
w.write_tensors_to_file(progress=True)
w.close()
