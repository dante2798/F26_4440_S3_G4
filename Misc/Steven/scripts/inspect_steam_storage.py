"""Summarise Steam app storage in an extracted stage folder WITHOUT printing secret values.

Reads a throw-away copy of databases/RKStorage (React Native AsyncStorage) and
shared_prefs/SecureStore.xml (Expo SecureStore). For each entry it prints the key,
value length, and a coarse value type (json-object / json-array / text / base64-like),
plus which top-level JSON field names exist. Values themselves are never printed.

Usage: python -I scripts/inspect_steam_storage.py work_steam/steam_emu_<stage>
"""
import json
import re
import shutil
import sqlite3
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

PKG = "com.valvesoftware.android.steam.community"
B64 = re.compile(r"^[A-Za-z0-9+/=_-]{24,}$")


def describe(value: str) -> str:
    try:
        obj = json.loads(value)
    except (ValueError, TypeError):
        return "base64-like" if B64.match(value or "") else "text"
    if isinstance(obj, dict):
        return "json-object fields=" + ",".join(sorted(obj.keys())[:25])
    if isinstance(obj, list):
        return f"json-array len={len(obj)}"
    return f"json-{type(obj).__name__}"


def rkstorage(stage: Path) -> None:
    src = stage / PKG / "databases" / "RKStorage"
    if not src.exists():
        print("RKStorage: not present")
        return
    with tempfile.TemporaryDirectory() as tmp:
        for f in src.parent.glob("RKStorage*"):
            shutil.copy2(f, tmp)
        con = sqlite3.connect(f"file:{Path(tmp) / 'RKStorage'}?mode=ro", uri=True)
        tables = [r[0] for r in con.execute("select name from sqlite_master where type='table'")]
        print(f"RKStorage tables: {tables}")
        if "catalystLocalStorage" in tables:
            for key, value in con.execute("select key, value from catalystLocalStorage order by key"):
                print(f"  {key:<60} len={len(value or ''):>7}  {describe(value)}")
        con.close()


def securestore(stage: Path) -> None:
    src = stage / PKG / "shared_prefs" / "SecureStore.xml"
    if not src.exists():
        print("SecureStore.xml: not present")
        return
    print("SecureStore.xml entries:")
    for el in ET.parse(src).getroot():
        name, text = el.get("name"), el.text or el.get("value") or ""
        print(f"  <{el.tag}> {name:<60} len={len(text):>5}  {describe(text)}")


if __name__ == "__main__":
    stage_dir = Path(sys.argv[1])
    print(f"== {stage_dir.name}")
    rkstorage(stage_dir)
    securestore(stage_dir)
