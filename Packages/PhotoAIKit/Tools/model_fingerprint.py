#!/usr/bin/env python3
"""Fingerprint model assets using PhotoAIKit's metadata schema."""

from __future__ import annotations

import hashlib
from pathlib import Path


def fingerprint_asset(asset_path: Path) -> dict[str, str]:
    if asset_path.is_file():
        return {"algorithm": "sha256", "value": _hash_file(asset_path).hexdigest()}
    if asset_path.is_dir():
        digest = hashlib.sha256()
        for file_path in sorted(
            path
            for path in asset_path.rglob("*")
            if path.is_file() and not path.is_symlink()
        ):
            relative_path = file_path.relative_to(asset_path).as_posix()
            digest.update(relative_path.encode())
            digest.update(b"\0")
            digest.update(str(file_path.stat().st_size).encode())
            digest.update(b"\0")
            with file_path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        return {
            "algorithm": "directory-tree-sha256-v1",
            "value": digest.hexdigest(),
        }
    raise FileNotFoundError(f"Model asset does not exist: {asset_path}")


def _hash_file(path: Path) -> "hashlib._Hash":
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest
