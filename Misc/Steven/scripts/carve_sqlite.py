"""Carve a SQLite DB for DELETED / residual records without a forensic suite.

For one .db file (+ its -wal/-journal) it reports, for each search pattern:
  live   = occurrences inside currently-live cell values (via a normal query/scan)
  total  = raw byte occurrences in the main DB file
  wal    = raw byte occurrences in the -wal sidecar
  freed  = total - live  -> copies sitting in free pages / freeblocks / slack,
           i.e. data that deletion did NOT actually scrub and that carving recovers.
Also prints freelist page count and total free bytes from the DB header.

Never prints the matched values - only names, counts and offsets. Works on a
THROW-AWAY copy (it opens read-only but treat the input as a copy anyway).

Usage:
  python -I scripts/carve_sqlite.py <file.db> pat1 pat2 ...
Patterns are plain ASCII substrings (e.g. refreshToken accessToken steamLoginSecure).
"""
import re
import sqlite3
import struct
import sys
from pathlib import Path


def header_info(data: bytes):
    if data[:16] != b"SQLite format 3\x00":
        return None
    page_size = struct.unpack(">H", data[16:18])[0]
    page_size = 65536 if page_size == 1 else page_size
    page_count = struct.unpack(">I", data[28:32])[0]
    freelist_pages = struct.unpack(">I", data[36:40])[0]
    return page_size, page_count, freelist_pages


def live_blob(db: Path) -> bytes:
    """Concatenate all current cell values as bytes, so we can count live hits."""
    chunks = []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        con.text_factory = bytes
        tables = [r[0] for r in con.execute(
            "select name from sqlite_master where type='table'")]
        for t in tables:
            try:
                for row in con.execute(f'select * from "{t.decode()}"'):
                    for v in row:
                        if isinstance(v, bytes):
                            chunks.append(v)
                        elif v is not None:
                            chunks.append(str(v).encode())
            except sqlite3.DatabaseError:
                continue
        con.close()
    except sqlite3.DatabaseError:
        pass
    return b"\x00".join(chunks)


def count(hay: bytes, needle: bytes) -> int:
    return len(re.findall(re.escape(needle), hay)) if needle else 0


def main() -> None:
    db = Path(sys.argv[1])
    patterns = [p.encode() for p in sys.argv[2:]]
    data = db.read_bytes()
    wal = db.with_name(db.name + "-wal")
    wal_data = wal.read_bytes() if wal.exists() else b""
    live = live_blob(db)

    hi = header_info(data)
    fl = 0
    print(f"== {db.name}  ({len(data)} bytes)")
    if hi:
        ps, pc, fl = hi
        print(f"   page_size={ps} pages={pc} freelist_pages={fl} "
              f"(~{fl * ps} bytes in free pages)")
    if wal_data:
        print(f"   WAL present: {wal.name} ({len(wal_data)} bytes)")
    # NOTE: total counts the whole file, which includes INDEX b-tree copies of a
    # column. So total > live does NOT by itself mean deleted data - a UNIQUE index
    # on the column doubles the count with live index entries. Only treat it as
    # recoverable deleted data when there are free pages (fl>0) or WAL-only hits.
    print(f"   {'pattern':<22}{'live':>6}{'total':>7}{'wal':>6}{'freed':>7}")
    for p in patterns:
        lv, tot, wl = count(live, p), count(data, p), count(wal_data, p)
        freed = max(tot - lv, 0)
        residual = (fl > 0 and freed > 0) or (wl > lv)
        flag = "  <-- residual in free space/WAL" if residual else \
               ("  (extra = live index copies, not deleted)" if freed > 0 else "")
        print(f"   {p.decode():<22}{lv:>6}{tot:>7}{wl:>6}{freed:>7}{flag}")


if __name__ == "__main__":
    main()
