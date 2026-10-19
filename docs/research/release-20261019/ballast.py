"""Hold GPU memory so that about TARGET MiB stays free (an 8 GB card emulation). python ballast.py TARGET_FREE_MIB"""
import subprocess, sys, time
import torch
target = int(sys.argv[1])
free = int(subprocess.check_output(["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"]).split()[0])
torch.cuda.init()
x = torch.empty(16, dtype=torch.uint8, device="cuda")   # context first
torch.cuda.synchronize()
free = int(subprocess.check_output(["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"]).split()[0])
hold = max(0, free - target)
b = torch.empty(hold * 2**20, dtype=torch.uint8, device="cuda")
b.fill_(1)
torch.cuda.synchronize()
now = int(subprocess.check_output(["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"]).split()[0])
print("ballast %d MiB, free now %d MiB" % (hold, now), flush=True)
while True:
    time.sleep(60)
