#!/usr/bin/env python3
"""Batch GeoIP lookup (MaxMind Country MMDB). stdin: one IP per line; stdout: IP<TAB>CC."""
from __future__ import annotations

import sys
from pathlib import Path


def lookup_mmdblookup(db_path: Path):
    import subprocess

    def one(ip: str) -> str:
        try:
            out = subprocess.check_output(
                [
                    "mmdblookup",
                    "-f",
                    str(db_path),
                    "--ip",
                    ip,
                    "country",
                    "iso_code",
                ],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2,
            )
            for line in out.splitlines():
                if "iso_code" in line and '"' in line:
                    return line.split('"')[1].upper()
        except Exception:
            pass
        return "??"

    return one


def lookup_maxminddb(db_path: Path):
    import maxminddb

    reader = maxminddb.open_database(str(db_path))

    def one(ip: str) -> str:
        try:
            rec = reader.get(ip)
            if rec and isinstance(rec.get("country"), dict):
                cc = rec["country"].get("iso_code")
                if cc:
                    return str(cc).upper()
        except Exception:
            pass
        return "??"

    return one


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: geoip-lookup-batch.py /path/to/GeoLite2-Country.mmdb", file=sys.stderr)
        return 2

    db = Path(sys.argv[1])
    if not db.is_file():
        print(f"MMDB not found: {db}", file=sys.stderr)
        return 1

    if True:
        try:
            import maxminddb  # noqa: F401

            fn = lookup_maxminddb(db)
        except ImportError:
            fn = lookup_mmdblookup(db)

    for line in sys.stdin:
        ip = line.strip()
        if not ip or ip.startswith("#"):
            continue
        print(f"{ip}\t{fn(ip)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
