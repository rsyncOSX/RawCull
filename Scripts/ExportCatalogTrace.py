#!/usr/bin/env python3
"""Export self-contained Instruments tables and benchmark context for catalog analysis."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

CORE = {"time-profile", "swiftui-updates", "swiftui-causes", "hitches", "potential-hangs",
        "thread-info", "process-info", "life-cycle-period", "dyld-library-load"}


def count_rows(path):
    """Validate even large XML exports without retaining their reference graphs in RAM."""
    count = 0
    parents = []
    with path.open("rb") as stream:
        for event, element in ET.iterparse(stream, events=("start", "end")):
            if event == "start":
                parents.append(element)
            else:
                if element.tag == "row":
                    count += 1
                    element.clear()
                    parents[-2].remove(element)
                parents.pop()
    return count


def selected(schema, all_tables=False):
    return all_tables or schema in CORE or any(
        word in schema.lower() for word in ("signpost", "os-log", "thread-state", "sched", "file-", "filesystem", "file_", "disk", "syscall", "system-call", "context-switch")
    )


def export(trace, xpath, path):
    # Each table gets a separate document, including its own schema and id/ref definitions.
    # A single all-table query can omit later schemas and share references across tables.
    result = subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace),
                             "--xpath", xpath, "--output", str(path)], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Export failed for {path.name}: {result.stderr or result.stdout}")
    return {"rows": count_rows(path), "bytes": path.stat().st_size,
            "diagnostics": (result.stdout + result.stderr).strip()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="New directory; existing outputs are never overwritten")
    parser.add_argument("--benchmark", type=Path, required=True, help="Benchmark output directory or results.json")
    parser.add_argument("--run", type=int, default=1, help="Recording number from the trace TOC")
    parser.add_argument("--all-tables", action="store_true", help="Export every recorded table, including raw kernel samples")
    parser.add_argument("--notes", default="", help="Cache state, thumbnail size, recording steps and observed delays")
    args = parser.parse_args(argv)
    manifest = None
    try:
        trace = args.trace.expanduser().resolve(strict=True)
        benchmark = args.benchmark.expanduser().resolve(strict=True)
        benchmark = benchmark / "results.json" if benchmark.is_dir() else benchmark
        report = json.loads(benchmark.read_text())
        if report.get("status") != "passed":
            raise ValueError("Use a completed, passed benchmark report")
        output = args.output.expanduser().resolve()
        if output == trace or trace in output.parents or output == benchmark.parent or benchmark.parent in output.parents:
            raise ValueError("Keep exports outside the trace bundle and benchmark output")
        output.mkdir(mode=0o700, parents=True, exist_ok=False)
        manifest = {"status": "exporting", "trace": str(trace), "benchmark": str(benchmark),
                    "benchmark_sha256": hashlib.sha256(benchmark.read_bytes()).hexdigest(),
                    "benchmark_version": report.get("benchmark_version"), "run": args.run,
                    "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "notes": args.notes, "tables": [], "warnings": []}
        shutil.copyfile(benchmark, output / "benchmark-results.json")
        if benchmark.with_name("report.md").exists():
            shutil.copyfile(benchmark.with_name("report.md"), output / "benchmark-report.md")
        toc = output / "trace-toc.xml"
        subprocess.run(["xcrun", "xctrace", "export", "--input", str(trace), "--toc", "--output", str(toc)], check=True)
        root = ET.parse(toc).getroot()
        run = root.find(f"./run[@number='{args.run}']")
        if run is None:
            raise ValueError(f"Recording {args.run} is absent; inspect trace-toc.xml")
        tables = run.findall("./data/table")
        schemas = {t.get("schema", "") for t in tables}
        manifest["recording"] = {e.tag: e.text for e in run.findall("./info/summary/*") if not len(e)}
        manifest["available_schemas"] = sorted(schemas)
        for index, table in enumerate(tables, 1):
            schema = table.get("schema", "")
            if not selected(schema, args.all_tables):
                continue
            filename = f"table-{index:03d}-{re.sub(r'[^a-zA-Z0-9_-]', '_', schema)}.xml"
            xpath = f'/trace-toc/run[@number="{args.run}"]/data/table[{index}]'
            print(f"Exporting {schema} → {filename}", flush=True)
            details = export(trace, xpath, output / filename)
            manifest["tables"].append({"schema": schema, "attributes": table.attrib,
                                       "file": filename, "xpath": xpath, **details})
        cpu = [t for t in manifest["tables"] if t["schema"] == "time-profile"]
        if not any(t["rows"] for t in cpu):
            raise ValueError("No Time Profiler samples exported; record Time Profiler and check the selected run")
        for schema in ("swiftui-updates", "swiftui-causes", "hitches", "potential-hangs"):
            if schema not in schemas:
                manifest["warnings"].append(f"{schema} was not recorded; it cannot be recovered by exporting")
        if not any("signpost" in s for s in schemas):
            manifest["warnings"].append("No signpost schema: exact phase alignment may require manual timeline inspection")
        if not any(any(w in s for w in ("thread-state", "sched", "syscall", "system-call", "file-", "filesystem", "file_", "disk", "context-switch")) for s in schemas):
            manifest["warnings"].append("No wait/I/O tables detected; CPU samples alone cannot identify a blocked read or lock")
        if report.get("benchmark_version", 1) < 2:
            manifest["warnings"].append("Legacy benchmark: CPU totals lack Mach timebase conversion; new encoding/grid phases are absent")
        manifest["status"] = "exported"
        print(f"Validated {len(manifest['tables'])} tables. Share {output}", flush=True)
        for warning in manifest["warnings"]:
            print(f"Warning: {warning}", flush=True)
        return 0
    except (OSError, ValueError, RuntimeError, ET.ParseError, subprocess.CalledProcessError) as error:
        if manifest is not None:
            manifest.update(status="failed", error=str(error))
        print(f"Trace export error: {error}", file=sys.stderr)
        return 2
    finally:
        if manifest is not None:
            (output / "export-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
