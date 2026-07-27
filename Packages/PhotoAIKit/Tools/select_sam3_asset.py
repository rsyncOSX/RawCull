#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from model_fingerprint import fingerprint_asset


def select_asset(bundle_dir: Path, asset_name: str) -> None:
    bundle_dir = bundle_dir.resolve()
    metadata_path = bundle_dir / "metadata.json"
    asset_path = bundle_dir / asset_name

    if not metadata_path.is_file():
        raise FileNotFoundError(f"Missing bundle metadata: {metadata_path}")
    if not asset_path.exists():
        raise FileNotFoundError(f"Missing SAM3 asset: {asset_path}")
    if asset_path.parent != bundle_dir:
        raise ValueError("Asset must be directly inside the SAM3 bundle directory.")

    with metadata_path.open() as stream:
        metadata = json.load(stream)

    metadata.setdefault("assets", {})["main"] = asset_name
    metadata.setdefault("asset_fingerprints", {})["main"] = fingerprint_asset(asset_path)

    with metadata_path.open("w") as stream:
        json.dump(metadata, stream, indent=2)
        stream.write("\n")

    print(f"Updated {metadata_path} assets.main and its verified fingerprint.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Select a SAM3 asset in a PhotoAIKit-compatible model bundle.",
    )
    parser.add_argument(
        "asset_name",
        help="Asset filename inside the SAM3 bundle, for example sam3_float16.aimodel.",
    )
    parser.add_argument(
        "--bundle-dir",
        type=Path,
        required=True,
        help="SAM3 bundle directory to update.",
    )
    args = parser.parse_args()
    select_asset(args.bundle_dir, args.asset_name)


if __name__ == "__main__":
    main()
