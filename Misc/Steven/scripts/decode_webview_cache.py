"""Decode Chromium/WebView "simple cache" entries (HTTP Cache/Cache_Data/*_0) to plain files.

For each entry: reads the URL key, the stored response headers, and the body; undoes
gzip / deflate / brotli content-encoding when possible; writes the body to
<out>/<entry name>.body and one row per entry to <out>/index.csv
(entry, url, status, content_type, content_encoding, decoded, body_bytes).
Read-only on the input folder.

Usage: python -I scripts/decode_webview_cache.py <Cache_Data folder> <out folder>
Brotli needs the 'brotli' package (pip install brotli); without it those bodies stay encoded.
"""
import csv
import re
import struct
import sys
import zlib
from pathlib import Path

try:
    import brotli  # type: ignore
except ImportError:
    brotli = None

INITIAL_MAGIC = 0xFCFB6D1BA7725C30
FINAL_MAGIC = 0xF4FA6F45970D41D8
EOF_SIZE = 24  # simple cache EOF record: magic(8) flags(4) crc(4) stream_size(4) pad(4)


def parse_entry(data: bytes):
    magic, _version, key_len, _key_hash = struct.unpack_from("<QIII", data, 0)
    if magic != INITIAL_MAGIC:
        return None
    header_len = 24  # magic(8) version(4) key_length(4) key_hash(4) padding(4)
    key = data[header_len:header_len + key_len].decode("utf-8", "replace")
    # The last EOF record describes stream 0 (headers); the one before it ends stream 1 (body).
    eof0 = data.rfind(struct.pack("<Q", FINAL_MAGIC))
    if eof0 < 0:
        return None
    stream0_size = struct.unpack_from("<I", data, eof0 + 16)[0]
    headers_start = eof0 - stream0_size
    eof1 = data.rfind(struct.pack("<Q", FINAL_MAGIC), 0, eof0)
    body_start = header_len + key_len
    body_end = eof1 if eof1 >= body_start else headers_start
    body = data[body_start:body_end]
    headers = data[headers_start:eof0]
    return key, headers, body


def header_value(raw: bytes, name: str) -> str:
    m = re.search(rb"(?i)\x00" + name.encode() + rb":\s*([^\x00]*)", raw)
    return m.group(1).decode("latin-1").strip() if m else ""


def decode(body: bytes, encoding: str):
    enc = encoding.lower()
    try:
        if enc == "gzip":
            return zlib.decompress(body, 31), True
        if enc == "deflate":
            return zlib.decompress(body), True
        if enc == "br":
            return (brotli.decompress(body), True) if brotli else (body, False)
    except Exception:
        return body, False
    return body, True


def main(src: Path, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for f in sorted(src.glob("*_0")):
        parsed = parse_entry(f.read_bytes())
        if not parsed:
            continue
        key, headers, body = parsed
        status = re.match(rb"HTTP/[\d.]+ (\d+)", headers.split(b"\x00", 1)[0] if headers else b"")
        enc = header_value(headers, "content-encoding")
        decoded, ok = decode(body, enc) if enc else (body, True)
        (out / f"{f.name}.body").write_bytes(decoded)
        rows.append({
            "entry": f.name, "url": re.sub(r"^.*? (?=https?://)", "", key),
            "status": status.group(1).decode() if status else "",
            "content_type": header_value(headers, "content-type"),
            "content_encoding": enc, "decoded": ok, "body_bytes": len(decoded),
        })
    with open(out / "index.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ["entry"])
        w.writeheader()
        w.writerows(rows)
    undecoded = sum(1 for r in rows if not r["decoded"])
    print(f"{src}: {len(rows)} entries, {undecoded} not decoded (brotli module: {bool(brotli)})")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
