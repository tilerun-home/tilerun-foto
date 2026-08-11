#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def manifest(root: Path) -> dict:
    files = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        files.append({"path": path.relative_to(root).as_posix(), "size": path.stat().st_size, "sha256": digest.hexdigest()})
    return {"file_count": len(files), "total_bytes": sum(item["size"] for item in files), "files": files}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["create", "verify"])
    parser.add_argument("root", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    actual = manifest(args.root)
    if args.action == "create":
        args.manifest.write_text(json.dumps(actual, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"{actual['file_count']} bestanden, {actual['total_bytes']} bytes")
        return
    expected = json.loads(args.manifest.read_text(encoding="utf-8"))
    if actual != expected:
        raise SystemExit("Herstelde mediabestanden wijken af van het back-upmanifest.")
    print(f"Mediarestore klopt: {actual['file_count']} bestanden, {actual['total_bytes']} bytes")


if __name__ == "__main__":
    main()
