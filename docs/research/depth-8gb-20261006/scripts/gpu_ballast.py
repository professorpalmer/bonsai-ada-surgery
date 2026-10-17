"""Hold N MiB of VRAM until killed (P166 spill-guard test): python gpu_ballast.py <MiB> <pidfile>"""
import os, sys, time
import torch
n = int(sys.argv[1])
t = torch.empty(n * 2**20, dtype=torch.uint8, device="cuda")
t.fill_(1)                      # touch it, so the driver makes it resident
torch.cuda.synchronize()
open(sys.argv[2], "w").write(str(os.getpid()))
print(f"ballast {n} MiB held", flush=True)
while True:
    time.sleep(5)
