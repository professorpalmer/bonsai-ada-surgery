"""Commit system memory without touching it, so the machine has the free commit of a smaller one (issue #16 test).

Usage: python ballast.py <GiB> <pidfile>   (runs until killed)
VirtualAlloc(MEM_RESERVE | MEM_COMMIT) charges the commit limit; the pages are never touched, so no physical RAM is used.
"""
import ctypes, os, sys, time

gib = float(sys.argv[1])
MEM_COMMIT, MEM_RESERVE, PAGE_READWRITE = 0x1000, 0x2000, 0x04
k32 = ctypes.windll.kernel32
k32.VirtualAlloc.restype = ctypes.c_void_p
k32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_uint32]
blocks = []
left = int(gib * 2**30)
while left > 0:
    n = min(left, 2**30)
    p = k32.VirtualAlloc(None, n, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE)
    if not p:
        print(f"commit failed after {len(blocks)} GiB", flush=True)
        break
    blocks.append(p)
    left -= n
open(sys.argv[2], "w").write(str(os.getpid()))
print(f"committed {len(blocks)} GiB", flush=True)
while True:
    time.sleep(60)
