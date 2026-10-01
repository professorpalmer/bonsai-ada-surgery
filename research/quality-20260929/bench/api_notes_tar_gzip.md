Python standard library notes (Python 3.12), for reference:

tarfile
- tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) writes an uncompressed tar stream into a
  binary file object such as io.BytesIO(). Mode "w" means no compression; use the gzip module separately if the
  outer stream must be gzip with specific header fields.
- tarfile.TarInfo(name) describes one member. Set .size (bytes), .mode (int), .mtime (int seconds), .uid, .gid
  (ints), .uname, .gname (str), and .type (tarfile.REGTYPE for a regular file). Then call
  tf.addfile(tarinfo, fileobj) where fileobj is io.BytesIO(content); addfile reads exactly .size bytes.
- With format=tarfile.USTAR_FORMAT the header magic is "ustar\0" with version "00"; names must fit the ustar
  limits or addfile raises ValueError. Closing the TarFile (or leaving a with-block) writes the two 512-byte
  zero end blocks and pads the archive to the record size (10240 bytes by default) with zeros.
- Constants that exist: tarfile.REGTYPE, tarfile.DIRTYPE, tarfile.USTAR_FORMAT, tarfile.GNU_FORMAT,
  tarfile.PAX_FORMAT, tarfile.BLOCKSIZE (512), tarfile.RECORDSIZE. There is no tarfile.default or
  tarfile.STATREG. TarInfo has no "data" argument and TarFile.addfile has no "data" keyword.
- To verify an archive: tarfile.open(fileobj=io.BytesIO(raw), mode="r:") then .getmembers() / .extractfile(m).read().

gzip
- gzip.compress(data, compresslevel=9, *, mtime=None): mtime=None uses the current time; pass mtime=0 for
  reproducible output. The header written by gzip.compress has no filename and no optional fields.
- gzip.decompress(data) checks the CRC32 and size trailer.
- gzip.GzipFile(fileobj=buf, mode="wb", mtime=0, filename="") also works; the default filename is taken from
  fileobj.name when present, so pass filename="" for no FNAME field. Read with mode "rb".

base64 / hashlib
- base64.b64decode(s, validate=True) rejects characters outside the alphabet; base64.b64encode(b).decode("ascii").
- hashlib.sha256(b).hexdigest() gives 64 lowercase hex characters.
