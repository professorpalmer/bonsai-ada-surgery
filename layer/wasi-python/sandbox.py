"""Run untrusted Python in CPython-on-WASI under wasmtime.

Isolation comes from WASI capabilities, not from promises in the code:
  - filesystem: only /usr/local/lib (the stdlib, read-only) and /work (a fresh temp dir per run) exist in the guest
  - network: WASI preview 1 has no sockets; nothing to reach
  - processes: no fork/exec in WASI
  - memory: hard linear-memory cap (store limits)
  - time: epoch interruption after `timeout` seconds of wall clock
"""
import os
import shutil
import tempfile
import threading

import wasmtime

HERE = os.path.dirname(os.path.abspath(__file__))
# VMware Labs CPython 3.12.0 WASI build (zlib compiled in), sha256 6c1cddbb... of the release tarball
RT = os.path.join(os.path.dirname(HERE), "runtime")   # created by layer/fetch_runtime.ps1
PYWASM = os.path.join(RT, "bin", "python-3.12.0.wasm")
LIB = os.path.join(RT, "usr", "local", "lib")

_engine = None
_module = None


def _load():
    global _engine, _module
    if _module is None:
        cfg = wasmtime.Config()
        cfg.epoch_interruption = True
        cfg.cache = True
        _engine = wasmtime.Engine(cfg)
        _module = wasmtime.Module.from_file(_engine, PYWASM)
    return _engine, _module


def run(files, argv, stdin=b"", timeout=8.0, mem_mb=128, max_out=1 << 20):
    """files: {relative name: bytes|str} placed in /work. argv: e.g. ["solution.py"].
    Returns dict(exit_code, stdout(bytes), stderr(bytes), timed_out, files_after{name: bytes})."""
    engine, module = _load()
    work = tempfile.mkdtemp(prefix="wasi-")
    io = tempfile.mkdtemp(prefix="wasi-io-")
    try:
        for name, data in files.items():
            p = os.path.join(work, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(data.encode("utf-8") if isinstance(data, str) else data)
        inp, outp, errp = (os.path.join(io, n) for n in ("in", "out", "err"))
        with open(inp, "wb") as f:
            f.write(stdin if isinstance(stdin, bytes) else stdin.encode("utf-8"))

        wasi = wasmtime.WasiConfig()
        wasi.argv = ["python"] + list(argv)
        wasi.env = [("PYTHONDONTWRITEBYTECODE", "1"), ("HOME", "/work")]
        wasi.stdin_file = inp
        wasi.stdout_file = outp
        wasi.stderr_file = errp
        wasi.preopen_dir(LIB, "/usr/local/lib", False)
        wasi.preopen_dir(work, "/work", True)
        wasi.preopen_dir(work, ".", True)   # relative paths resolve in the workspace (cwd), as on a normal run

        store = wasmtime.Store(engine)
        store.set_wasi(wasi)
        store.set_limits(memory_size=mem_mb * 1024 * 1024)
        store.set_epoch_deadline(1)
        linker = wasmtime.Linker(engine)
        linker.define_wasi()
        inst = linker.instantiate(store, module)

        timer = threading.Timer(timeout, engine.increment_epoch)
        timer.start()
        code, timed_out = 0, False
        try:
            inst.exports(store)["_start"](store)
        except wasmtime.ExitTrap as e:
            code = e.code
        except wasmtime.Trap as e:
            timed_out = "interrupt" in str(e).lower()
            code = 124 if timed_out else 134
            with open(errp, "ab") as f:
                f.write(f"\n[sandbox trap: {e}]".encode()[:2000])
        except wasmtime.WasmtimeError as e:
            code = 134
            with open(errp, "ab") as f:
                f.write(f"\n[sandbox error: {e}]".encode()[:2000])
        finally:
            timer.cancel()
        out = open(outp, "rb").read()[:max_out]
        err = open(errp, "rb").read()[:max_out]
        after = {}
        for root, _, names in os.walk(work):
            for n in names:
                full = os.path.join(root, n)
                if os.path.getsize(full) <= 4 << 20:
                    after[os.path.relpath(full, work).replace("\\", "/")] = open(full, "rb").read()
        return {"exit_code": code, "stdout": out, "stderr": err, "timed_out": timed_out, "files_after": after}
    finally:
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(io, ignore_errors=True)
