"""Canary checks: the sandbox must allow ordinary computation and deny everything else."""
import json
import sandbox

KEYFILE = r"C:\Users\pwall\Projects\bonsai-2-27b-serve\artifacts\api_key.txt"
C = {
    "hello": ("print('hi', 6*7)", lambda r: r["exit_code"] == 0 and r["stdout"].strip() == b"hi 42"),
    "stdin_json": ("import json,sys; d=json.load(sys.stdin); print(json.dumps({'n': d['x']+1}))",
                   lambda r: r["stdout"].strip() == b'{"n": 2}'),
    "stdlib_needed": ("import tarfile,gzip,io,base64,hashlib,zlib,decimal,re,csv,struct\n"
                      "b=io.BytesIO(); t=tarfile.open(fileobj=b,mode='w');\n"
                      "ti=tarfile.TarInfo('a.txt'); ti.size=2; t.addfile(ti, io.BytesIO(b'hi')); t.close()\n"
                      "print(len(gzip.compress(b.getvalue()))>0, hashlib.sha256(b'x').hexdigest()[:8])",
                      lambda r: r["exit_code"] == 0 and r["stdout"].startswith(b"True 2d711642")),
    "write_work_ok": ("open('/work/out.txt','w').write('ok'); print(open('/work/out.txt').read())",
                      lambda r: r["stdout"].strip() == b"ok" and r["files_after"].get("out.txt") == b"ok"),
    "relative_paths": ("open('note.txt','w').write('x'); import os; print(open('note.txt').read(), os.path.exists('main.py'), sorted(os.listdir('.')))",
                       lambda r: r["exit_code"] == 0 and r["stdout"].startswith(b"x True") and b"Users" not in r["stdout"]),
    "relative_escape_denied": ("print(open('../../../../Windows/win.ini').read())", lambda r: r["exit_code"] != 0),
    "host_key_denied": (f"print(open({KEYFILE!r}).read())", lambda r: r["exit_code"] != 0 and b"Error" in r["stderr"]),
    "host_root_denied": ("import os; print(os.listdir('/'))",
                         lambda r: b"Users" not in r["stdout"] and b"Windows" not in r["stdout"]),
    "parent_escape_denied": ("print(open('/work/../../../../Windows/win.ini').read())",
                             lambda r: r["exit_code"] != 0),
    "lib_readonly": ("open('/usr/local/lib/python3.12/evil.py','w').write('x')", lambda r: r["exit_code"] != 0),
    "network_denied": ("import socket; s=socket.create_connection(('1.1.1.1',80),timeout=2); print('CONNECTED')",
                       lambda r: b"CONNECTED" not in r["stdout"] and r["exit_code"] != 0),
    "subprocess_denied": ("import subprocess; print(subprocess.run(['cmd','/c','echo PWNED'],capture_output=True))",
                          lambda r: b"PWNED" not in r["stdout"] and r["exit_code"] != 0),
    "timeout": ("while True: pass", lambda r: r["timed_out"] and r["exit_code"] == 124),
    "memory_cap": ("x = bytearray(512*1024*1024); print('ALLOCATED')", lambda r: b"ALLOCATED" not in r["stdout"]),
}
ok = True
for name, (code, check) in C.items():
    r = sandbox.run({"main.py": code}, ["/work/main.py"], stdin=b'{"x": 1}', timeout=5)
    passed = bool(check(r))
    ok &= passed
    print(f"{'PASS' if passed else 'FAIL'} {name:22s} exit={r['exit_code']} out={r['stdout'][:60]!r} err={r['stderr'][-120:]!r}")
print("ALL PASS" if ok else "SOME FAILED")
