"""Inspect WoW client database files (DBC/DB2) for the Zone Atlas (issue #48).

Research tooling only. It never writes into the addon, and its output is
evidence to review, not verified data. It reads:

  * headers of WDBC (.dbc), WDB2, WDB5/WDB6 and WDC1-WDC5 (.db2) files:
    magic, record and field counts, record size, string table size, and the
    table and layout hashes that identify a file's schema and build family;
  * whole WDBC files: fixed-size records plus a string block. String fields
    are found by inspection (values that point at the start of a string),
    never assumed from a layout.

For AreaTable it then compares each record against Dawnward's expected
names (Core/Atlas.lua) and flags records on maps outside the Classic world
continents, which usually means a later expansion or an instance.

Usage:
  python tools/atlas/client_db.py inspect <file> [<file> ...]      header report (JSON)
  python tools/atlas/client_db.py areatable <areatable.dbc> [--out report.json]
  python tools/atlas/client_db.py selftest    (also checks the SHA-256 of the in-game evidence files)

Nothing is downloaded and no file is modified. Unknown formats (such as
.scn) are reported by their first bytes only.
"""

import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ATLAS_LUA = ROOT / "DawnwardChronicles" / "Core" / "Atlas.lua"
# Owner-run in-game evidence, kept verbatim (Core/Atlas.lua, Atlas.EVIDENCE).
EVIDENCE_DIR = ROOT / "tools" / "atlas" / "evidence"

# Map (continent) IDs of the Classic world. Anything else in AreaTable is
# an instance, a battleground, a test map, or a later expansion's world.
CLASSIC_WORLD_MAPS = {0: "Eastern Kingdoms", 1: "Kalimdor"}
LATER_WORLD_MAPS = {530: "Outland / TBC zones", 571: "Northrend", 646: "Deepholm", 730: "Maelstrom",
                    860: "Wandering Isle", 870: "Pandaria", 1116: "Draenor", 1220: "Broken Isles"}

WDB2_HEADER = struct.Struct("<4s I I I I I I I I I I")
WDB5_HEADER = struct.Struct("<4s I I I I I I I I H H")


def read_header(data):
    """Header fields of a client database file, or the raw magic if unknown."""
    magic = data[:4]
    name = magic.decode("latin-1")
    if magic == b"WDBC":
        records, fields, size, strings = struct.unpack_from("<4I", data, 4)
        return {"format": "WDBC", "records": records, "fields": fields, "record_size": size,
                "string_block": strings, "expected_length": 20 + records * size + strings,
                "actual_length": len(data)}
    if magic == b"WDB2":
        (_, records, fields, size, strings, table_hash, build, timestamp, min_id, max_id,
         locale) = WDB2_HEADER.unpack_from(data)
        return {"format": "WDB2", "records": records, "fields": fields, "record_size": size,
                "string_block": strings, "table_hash": f"{table_hash:08X}", "build": build,
                "min_id": min_id, "max_id": max_id, "locale": locale}
    if magic in (b"WDB5", b"WDB6"):
        (_, records, fields, size, strings, table_hash, layout_hash, min_id, max_id, locale,
         copy_size) = WDB5_HEADER.unpack_from(data)
        return {"format": name, "records": records, "fields": fields, "record_size": size,
                "string_block": strings, "table_hash": f"{table_hash:08X}",
                "layout_hash": f"{layout_hash:08X}", "min_id": min_id, "max_id": max_id, "locale": locale}
    if re.fullmatch(rb"WDC[1-9]", magic):
        # WDC1-WDC4: the counts follow the magic. WDC5 adds a version number
        # and a 128-byte schema string first (per the wowdev.wiki DB2 page;
        # confirm against a real file before relying on WDC5 output).
        offset = 4 + (4 + 128 if magic == b"WDC5" else 0)
        fields = struct.unpack_from("<I I I I I I I I I H H", data, offset)
        records, field_count, size, strings, table_hash, layout_hash, min_id, max_id, locale, flags, id_index = fields
        return {"format": name, "records": records, "fields": field_count, "record_size": size,
                "string_block": strings, "table_hash": f"{table_hash:08X}",
                "layout_hash": f"{layout_hash:08X}", "min_id": min_id, "max_id": max_id,
                "locale": locale, "flags": flags, "id_index": id_index,
                "note": "header only; record parsing for WDC files is not implemented"}
    return {"format": "unknown", "magic_hex": data[:16].hex(), "length": len(data)}


def read_wdbc(data):
    """Records (lists of uint32 field values) and the string block of a WDBC file."""
    header = read_header(data)
    if header["format"] != "WDBC":
        raise ValueError("not a WDBC file")
    if header["record_size"] != header["fields"] * 4:
        raise ValueError("record size is not 4 bytes per field; this layout is not supported")
    if header["expected_length"] != header["actual_length"]:
        raise ValueError(f"length {header['actual_length']} does not match header ({header['expected_length']})")
    start = 20
    records = []
    for i in range(header["records"]):
        records.append(list(struct.unpack_from(f"<{header['fields']}I", data, start + i * header["record_size"])))
    block = data[start + header["records"] * header["record_size"]:]
    return header, records, block


def string_at(block, offset):
    if offset <= 0 or offset >= len(block) or block[offset - 1] != 0:
        return None
    end = block.find(b"\0", offset)
    if end <= offset:
        return None
    try:
        return block[offset:end].decode("utf-8")
    except UnicodeDecodeError:
        return None


def string_fields(records, block, sample=200):
    """Field indexes whose non-zero values all point at the start of a string."""
    out = []
    if not records:
        return out
    for index in range(len(records[0])):
        values = [r[index] for r in records[:sample] if r[index]]
        if values and all(string_at(block, v) is not None for v in values):
            out.append(index)
    return out


def expected_names():
    """Dawnward's expected enUS names, parsed from Core/Atlas.lua (areas only)."""
    text = ATLAS_LUA.read_text(encoding="utf-8")
    areas = text[text.index("areas = {", text.index("Atlas.EXPECTED")):]
    areas = areas[:areas.index("},")]
    return {int(i): n.replace('\\"', '"') for i, n in re.findall(r'\[(\d+)\] = "((?:[^"\\]|\\.)*)"', areas)}


def areatable_report(data):
    header, records, block = read_wdbc(data)
    names = string_fields(records, block)
    if not names:
        raise ValueError("no string field found; is this AreaTable?")
    name_field = names[0]
    expected = expected_names()
    by_map, rows, checks = {}, [], {"agree": [], "differ": [], "absent": []}
    for r in records:
        area_id, map_id, parent = r[0], r[1], r[2]
        name = string_at(block, r[name_field])
        world = ("classic" if map_id in CLASSIC_WORLD_MAPS else
                 "later expansion" if map_id in LATER_WORLD_MAPS else "instance or other")
        by_map[world] = by_map.get(world, 0) + 1
        rows.append({"id": area_id, "map": map_id, "parent": parent, "name": name, "world": world})
    known = {row["id"]: row for row in rows}
    for area_id, name in sorted(expected.items()):
        row = known.get(area_id)
        if not row:
            checks["absent"].append(area_id)
        elif row["name"] == name:
            checks["agree"].append(area_id)
        else:
            checks["differ"].append({"id": area_id, "expected": name, "file": row["name"]})
    return {
        "header": header,
        "assumed_columns": {"id": 0, "map": 1, "parent": 2, "name": name_field,
                            "note": "id, map and parent columns follow the 1.x-3.x WDBC AreaTable layout; "
                                    "check them against WoWDBDefs for the file's build before trusting them"},
        "worlds": by_map,
        "max_id": max((row["id"] for row in rows), default=0),
        "dawnward_expected": {k: (len(v) if isinstance(v, list) else v) for k, v in checks.items()},
        "differences": checks["differ"],
        "absent_ids": checks["absent"],
        "records": rows,
    }


def build_wdbc(records, strings):
    """A WDBC file from records (lists of ints, with ('s', text) for strings). For tests."""
    block = bytearray(b"\0")
    encoded = []
    for r in records:
        row = []
        for v in r:
            if isinstance(v, tuple):
                row.append(len(block))
                block += v[1].encode("utf-8") + b"\0"
            else:
                row.append(v)
        encoded.append(row)
    for s in strings:
        block += s.encode("utf-8") + b"\0"
    fields = len(encoded[0])
    out = bytearray(b"WDBC" + struct.pack("<4I", len(encoded), fields, fields * 4, len(block)))
    for row in encoded:
        out += struct.pack(f"<{fields}I", *row)
    return bytes(out + block)


def check_evidence():
    """Every Atlas.EVIDENCE file exists and has the SHA-256 published in #48."""
    text = ATLAS_LUA.read_text(encoding="utf-8")
    block = text[text.index("Atlas.EVIDENCE = {"):]
    block = block[:block.index("\n}\n")]
    entries = re.findall(r'file = "([^"]+)".*?sha256 = "([0-9a-f]{64})"', block, re.S)
    assert len(entries) == 2, entries
    for name, digest in entries:
        data = (EVIDENCE_DIR / name).read_bytes()
        got = hashlib.sha256(data).hexdigest()
        assert got == digest, f"{name}: sha256 {got}, expected {digest}"
    return len(entries)


def selftest():
    data = build_wdbc([
        [87, 0, 12, 0, ("s", "Goldshire"), 0],
        [9, 0, 12, 0, ("s", "Northshire Valley"), 0],
        [69, 0, 44, 0, ("s", "Lakeshire (renamed)"), 0],
        [3430, 530, 0, 0, ("s", "Eversong Woods"), 0],
        [2017, 329, 0, 0, ("s", "Stratholme"), 0],
    ], [])
    report = areatable_report(data)
    assert report["header"]["records"] == 5
    assert report["assumed_columns"]["name"] == 4, report["assumed_columns"]
    assert report["worlds"] == {"classic": 3, "later expansion": 1, "instance or other": 1}, report["worlds"]
    assert report["dawnward_expected"]["agree"] == 2
    assert report["differences"] == [{"id": 69, "expected": "Lakeshire", "file": "Lakeshire (renamed)"}]
    assert 2979 in report["absent_ids"]
    assert read_header(b"WDC3" + bytes(80))["format"] == "WDC3"
    assert read_header(b"\x01\x02\x03\x04rest")["format"] == "unknown"
    try:
        read_wdbc(data[:-3])
        raise AssertionError("truncated file accepted")
    except ValueError:
        pass
    files = check_evidence()
    print(f"client_db selftest: ok (evidence files: {files} verified)")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("inspect", "areatable", "selftest"):
        print(__doc__)
        return 2
    if argv[1] == "selftest":
        selftest()
        return 0
    if argv[1] == "inspect":
        report = {p: read_header(Path(p).read_bytes()) for p in argv[2:]}
        print(json.dumps(report, indent=2))
        return 0
    path = Path(argv[2])
    report = areatable_report(path.read_bytes())
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
    text = json.dumps(report, indent=2, ensure_ascii=False)
    if out:
        Path(out).write_text(text, encoding="utf-8")
        print(f"wrote {out}: {report['header']['records']} records, worlds {report['worlds']}, "
              f"expected names {report['dawnward_expected']}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
