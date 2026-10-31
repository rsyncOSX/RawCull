#!/usr/bin/env python3
"""Build the production renderer and pinned legacy parser, then measure read-only RAW inputs.

Example:
  python3 Scripts/RunRAW9PreviewBenchmark.py /path/to/raws --parser-source /path/to/pinned/RawParserKit --output /tmp/raw9-results

Runs optimized standalone stage measurements, not app first-paint/UI measurements.
OS and storage caches are not flushed. All output goes into --output.
"""
import argparse
import json
import hashlib
from pathlib import Path
import platform
import statistics
import subprocess


def run(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--parser-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--files", type=int, default=6)
    parser.add_argument("--passes", type=int, default=3)
    parser.add_argument("--modes", nargs="+", choices=["baseline", "native", "direct-native", "fit", "revisit", "validate", "validate-fit"], default=["baseline", "native", "fit", "revisit", "validate", "validate-fit"])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    pins = json.loads((root / "RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
    expected = next(pin["state"]["revision"] for pin in pins["pins"] if pin["identity"] == "rawparserkit")
    revision = subprocess.check_output(["git", "-C", str(args.parser_source), "rev-parse", "HEAD"], text=True).strip()
    if revision != expected:
        raise SystemExit(f"Use pinned RawParserKit {expected}; provided checkout is {revision}")
    if subprocess.check_output(["git", "-C", str(args.parser_source), "status", "--porcelain", "--", "Sources"], text=True).strip():
        raise SystemExit("Parser sources must be clean for a reproducible baseline")
    common = ["xcrun", "swiftc", "-O", "-swift-version", "6", "-default-isolation", "MainActor",
              "-enable-upcoming-feature", "NonisolatedNonsendingByDefault", "-enable-upcoming-feature", "InferIsolatedConformances",
              "-module-cache-path", out / "modules"]
    run(common + ["-emit-library", "-emit-module", "-module-name", "RawParserKit"]
        + sorted((args.parser_source / "Sources/RawParserKit").rglob("*.swift"))
        + ["-o", out / "libRawParserKit.dylib", "-emit-module-path", out / "RawParserKit.swiftmodule"])
    binary = out / "raw9-preview-benchmark"
    run(common + ["-parse-as-library", "-I", out, "-L", out, "-lRawParserKit", "-Xlinker", "-rpath", "-Xlinker", out,
        root / "RawCull/Model/Handlers/RAWPreviewRenderer.swift", root / "Scripts/RAW9PreviewBenchmark.swift", "-o", binary])
    source_hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [
        root / "RawCull/Model/Handlers/RAWPreviewRenderer.swift", root / "Scripts/RAW9PreviewBenchmark.swift"]}
    summaries = {}
    for mode in args.modes:
        with (out / f"{mode}.jsonl").open("w") as stdout, (out / f"{mode}.stderr.log").open("w") as stderr:
            run([binary, args.folder.resolve(), mode, args.files, 1 if mode.startswith("validate") else args.passes, out], stdout=stdout, stderr=stderr)
        rows = [json.loads(line) for line in (out / f"{mode}.jsonl").read_text().splitlines()]
        summaries[mode] = {"samples": len(rows), "delivery_ms_median": statistics.median(row["delivery_ms"] for row in rows),
            "delivery_ms_min": min(row["delivery_ms"] for row in rows), "delivery_ms_max": max(row["delivery_ms"] for row in rows),
            "materialized_ms_median": statistics.median(row["materialized_ms"] for row in rows),
            "process_peak_rss_bytes": max(row["process_peak_rss_bytes"] for row in rows)}
        print(mode, summaries[mode], flush=True)
    (out / "summary.json").write_text(json.dumps({"macOS": platform.mac_ver()[0], "parser_revision": revision, "source_sha256": source_hashes,
        "folder": str(args.folder.resolve()), "files": args.files, "passes": args.passes, "results": summaries}, indent=2) + "\n")


if __name__ == "__main__":
    main()
