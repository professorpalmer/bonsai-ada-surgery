import base64, gzip, hashlib, io, json, sys, tarfile
try:
    req = json.load(sys.stdin)
    members = sorted(req["members"], key=lambda m: m["path"])
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tf:
        for m in members:
            data = base64.b64decode(m["content_b64"], validate=True)
            ti = tarfile.TarInfo(m["path"]); ti.size = len(data); ti.mode = m["mode"]
            ti.mtime = 0; ti.uid = ti.gid = 0; ti.uname = ti.gname = ""; ti.type = tarfile.REGTYPE
            tf.addfile(ti, io.BytesIO(data))
    gz = gzip.compress(buf.getvalue(), mtime=0)
    print(json.dumps({"format": "tar+gzip", "bundle_b64": base64.b64encode(gz).decode(), "sha256": hashlib.sha256(gz).hexdigest()}))
except Exception:
    print(json.dumps({"error": "invalid_request"}))
