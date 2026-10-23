#!/usr/bin/env python3
"""Build and run RawCull's opt-in real-catalog integration benchmark."""
import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
VERSION = 1
REQUIRED_PHASES = {
    "catalog.discovery", "catalog.metadata", "preload.emptyDiskCache", "preload.warmDiskCache",
    "browse.disk", "browse.revisit", "browse.duringPreload", "browse.noSourceFallback",
    "preload.withBrowsing", "navigation.build", "navigation.selectionAndControls",
    "navigation.ratingFilter", "navigation.reuseAndInvalidation", "zoom.previewReady",
    "preload.cancelAndDrain", "preload.recovery", "grid.resize",
}
# These are structural assertions, not useful timing measurements.
CHECK_ONLY = {"browse.noSourceFallback", "navigation.reuseAndInvalidation", "run.error"}


def command_text(arguments):
    return subprocess.check_output(arguments, cwd=ROOT, text=True, stderr=subprocess.STDOUT).strip()


def catalog_manifest(directory):
    directory = directory.expanduser().resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("Catalog must be a directory")
    files = []
    for path in sorted(directory.iterdir(), key=lambda p: p.name):
        if path.suffix.lower() == ".arw" and not path.name.startswith(".") and path.is_file():
            stat = path.stat()
            files.append({"name": path.name, "bytes": stat.st_size, "modified_ns": stat.st_mtime_ns})
    if not files:
        raise ValueError("Catalog contains no regular ARW files (only the supplied folder is scanned)")
    if any(item["bytes"] == 0 for item in files):
        raise ValueError("Catalog contains empty ARW files")
    digest = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    return {"directory": str(directory), "files": files, "file_count": len(files),
            "total_bytes": sum(item["bytes"] for item in files), "fingerprint": digest,
            "fingerprint_method": "SHA-256 of sorted filenames, sizes and modification times; not file contents"}


def source_identity():
    status = command_text(["git", "status", "--porcelain"])
    # Includes modified and untracked source so two dirty worktrees remain distinguishable.
    paths = command_text(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"]).split("\0")
    digest = hashlib.sha256()
    for name in sorted(set(paths)):
        path = ROOT / name
        if name and path.is_file() and path.suffix in {".swift", ".py", ".xctestplan", ".pbxproj", ".resolved"}:
            digest.update(name.encode())
            digest.update(b"\0")
            digest.update(path.read_bytes())
    harness = hashlib.sha256()
    for path in sorted((ROOT / "RawCullPerformanceTests").glob("*.swift")):
        harness.update(path.read_bytes())
    for name in ("Scripts/RunCatalogPerformance.py", "CatalogPerformance.xctestplan",
                 "RawCull.xcodeproj/xcshareddata/xcschemes/RawCullPerformance.xcscheme"):
        harness.update((ROOT / name).read_bytes())
    return {"benchmark_sha256": harness.hexdigest(), "commit": command_text(["git", "rev-parse", "HEAD"]),
            "status": status, "source_sha256": digest.hexdigest(),
            "xcode": command_text(["xcodebuild", "-version"])}


def distribution(values):
    values = sorted(values)
    return {"count": len(values), "median_ms": statistics.median(values),
            "p95_ms": values[max(0, math.ceil(len(values) * .95) - 1)], "max_ms": values[-1]}


def summarize(output, runs):
    per_phase = {}
    resources = []
    failures = []
    raw_runs = []
    for run in range(1, runs + 1):
        path = output / f"run-{run}" / "results.json"
        if not path.exists():
            failures.append(f"Run {run}: missing results; test may not have executed")
            continue
        try:
            result = json.loads(path.read_text())
            if not isinstance(result.get("metrics"), list) or not isinstance(result.get("resources"), list):
                raise ValueError("Missing metrics or resource samples")
        except (OSError, ValueError) as error:
            failures.append(f"Run {run}: unreadable results: {error}")
            continue
        cancellation_path = path.with_name("cancellation-results.json")
        raw_runs.append({"run": run, **result,
                         "cancellation": json.loads(cancellation_path.read_text()) if cancellation_path.exists() else None})
        phases = {metric["phase"] for metric in result["metrics"]}
        for missing in sorted(REQUIRED_PHASES - phases):
            failures.append(f"Run {run}: missing phase {missing}")
        for metric in result["metrics"]:
            if not metric["succeeded"]:
                failures.append(f"Run {run}: {metric['phase']}: {metric['detail']}")
            if metric["phase"] not in CHECK_ONLY:
                per_phase.setdefault(metric["phase"], []).append(metric["milliseconds"])
        samples = result["resources"]
        footprints = [item["footprintBytes"] for item in samples if item.get("footprintBytes") is not None]
        reads = [item["diskReadBytes"] for item in samples if item.get("diskReadBytes") is not None]
        writes = [item["diskWriteBytes"] for item in samples if item.get("diskWriteBytes") is not None]
        cpus = [item["cpuSeconds"] for item in samples if item.get("cpuSeconds") is not None]
        resources.append({"run": run, "sample_count": len(samples),
                          "initial_footprint_bytes": footprints[0] if footprints else None,
                          "sampled_peak_footprint_bytes": max(footprints) if footprints else None,
                          "final_footprint_bytes": footprints[-1] if footprints else None,
                          "cpu_seconds_delta": cpus[-1] - cpus[0] if cpus else None,
                          "disk_read_bytes_delta": reads[-1] - reads[0] if reads else None,
                          "disk_write_bytes_delta": writes[-1] - writes[0] if writes else None,
                          "peak_preload_saves": result["peakSaves"], "operation_counts": result["counts"]})
    return {"phases": {name: distribution(values) for name, values in sorted(per_phase.items())},
            "resources": resources, "failures": failures, "runs": raw_runs}


def compare(current, baseline, maximum):
    differences = []
    for key in ("benchmark_version", "settings", "machine"):
        if current[key] != baseline.get(key):
            differences.append(key)
    if current["catalog"]["fingerprint"] != baseline.get("catalog", {}).get("fingerprint"):
        differences.append("catalog fingerprint")
    # Source path affects production cache identity and may imply different storage.
    if current["catalog"]["directory"] != baseline.get("catalog", {}).get("directory"):
        differences.append("catalog directory/storage")
    if current["source"]["xcode"] != baseline.get("source", {}).get("xcode"):
        differences.append("Xcode/toolchain")
    if current["source"].get("benchmark_sha256") != baseline.get("source", {}).get("benchmark_sha256"):
        differences.append("benchmark implementation")
    if baseline.get("status") != "passed":
        differences.append("baseline did not pass")
    if differences:
        raise ValueError("Baseline is not comparable: " + ", ".join(differences))
    changes = []
    for name, result in current["summary"]["phases"].items():
        previous = baseline["summary"]["phases"].get(name)
        if previous is None:
            raise ValueError(f"Baseline is missing phase: {name}")
        for statistic in ("median_ms", "p95_ms", "max_ms"):
            old, new = previous[statistic], result[statistic]
            percent = (new / old - 1) * 100 if old > 0 else None
            # Gate medians only, and ignore sub-5 ms increases to avoid trivial timing noise.
            regression = (statistic == "median_ms" and maximum is not None and percent is not None
                          and percent > maximum and new - old > 5)
            changes.append({"phase": name, "statistic": statistic, "before_ms": old, "after_ms": new,
                            "change_percent": percent, "regression": regression})
    return changes


def compare_resources(current, baseline):
    changes = []
    for field in ("initial_footprint_bytes", "sampled_peak_footprint_bytes", "final_footprint_bytes",
                  "cpu_seconds_delta", "disk_read_bytes_delta", "disk_write_bytes_delta", "peak_preload_saves"):
        old_values = [r[field] for r in baseline["summary"].get("resources", []) if r.get(field) is not None]
        new_values = [r[field] for r in current["summary"].get("resources", []) if r.get(field) is not None]
        old = statistics.median(old_values) if old_values else None
        new = statistics.median(new_values) if new_values else None
        percent = (new / old - 1) * 100 if old and new is not None else None
        changes.append({"metric": field, "before": old, "after": new, "change_percent": percent})
    return changes


def markdown(report):
    lines = ["# RawCull real-catalog performance", "", f"Status: **{report['status']}**", "",
             f"Started (UTC): {report['started_utc']}", f"Commit: `{report['source']['commit']}`",
             f"Source fingerprint: `{report['source']['source_sha256']}`",
             f"Catalog: `{report['catalog']['directory']}`",
             f"ARWs: {report['catalog']['file_count']}; bytes: {report['catalog']['total_bytes']}",
             f"Catalog fingerprint: `{report['catalog']['fingerprint']}`", "",
             "Release integration benchmark with testability enabled, coverage and parallel testing disabled.",
             "Measures production components and image-ready latency, not first painted frame or frame smoothness.",
             "Empty disk cache means a new benchmark thumbnail cache; OS/parser caches are not flushed.",
             "Runs share a process; later runs can benefit from OS/parser warm-up. Keep run order consistent.",
             "Per-file metrics include measurement/logging overhead. Times are monotonic wall durations, not CPU weights.", "",
             "| Phase | Samples | Median ms | p95 ms | Worst ms |", "| --- | ---: | ---: | ---: | ---: |"]
    for name, values in report["summary"]["phases"].items():
        lines.append(f"| {name} | {values['count']} | {values['median_ms']:.3f} | {values['p95_ms']:.3f} | {values['max_ms']:.3f} |")
    lines += ["", "## Resources", "", "Process footprint sampled every 100 ms; brief peaks may be missed. Includes the test host.", ""]
    for resource in report["summary"]["resources"]:
        peak = resource["sampled_peak_footprint_bytes"]
        cpu = resource["cpu_seconds_delta"]
        lines.append(f"- Run {resource['run']}: sampled peak {peak / 1048576:.1f} MiB; CPU {cpu:.3f} s; "
                     f"peak preload saves {resource['peak_preload_saves']}." if peak is not None and cpu is not None
                     else f"- Run {resource['run']}: process resource measurement unavailable.")
    if report.get("comparison"):
        lines += ["", "## Baseline comparison", "", "Negative changes mean less elapsed time.", "",
                  "| Phase | Statistic | Before ms | After ms | Change |", "| --- | --- | ---: | ---: | ---: |"]
        for change in report["comparison"]:
            percent = change["change_percent"]
            label = f"{percent:+.1f}%" if percent is not None else "unavailable"
            lines.append(f"| {change['phase']} | {change['statistic']} | {change['before_ms']:.3f} | "
                         f"{change['after_ms']:.3f} | {label}{' REGRESSION' if change['regression'] else ''} |")
    if report.get("resource_comparison"):
        lines += ["", "Resource comparison uses medians across repetitions; units are encoded in metric names.", "",
                  "| Resource | Before | After | Change |", "| --- | ---: | ---: | ---: |"]
        for item in report["resource_comparison"]:
            percent = item["change_percent"]
            change = f"{percent:+.1f}%" if percent is not None else "unavailable"
            lines.append(f"| {item['metric']} | {item['before']} | {item['after']} | {change} |")
    lines += ["", "## Checks and failures", ""]
    lines += [f"- {failure}" for failure in report["summary"]["failures"]] or ["All recorded correctness checks passed."]
    lines += ["", "## Reproducibility", "", "```json", json.dumps({
        "settings": report["settings"], "machine": report["machine"], "source": report["source"],
        "command": report["command"], "notes": report["notes"],
    }, indent=2), "```", "",
        "Full per-file timings, counters, memory/CPU samples and manifest: results.json and run-*/events.jsonl.",
        "Cancellation decode results are separate because interrupted decodes may legitimately return no image.",
        "Build/test diagnostics: xcodebuild.log and tests.xcresult. Source catalog files are read only.", ""]
    return "\n".join(lines)


def run_process(command, environment, output, timeout):
    with (output / "xcodebuild.log").open("w") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"Build/test exceeded {timeout} seconds")
                try:
                    return process.wait(timeout=min(30, remaining))
                except subprocess.TimeoutExpired:
                    print(f"Benchmark running; diagnostics: {output / 'xcodebuild.log'}", flush=True)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", type=Path, help="Folder containing real ARW files; nonrecursive")
    parser.add_argument("--output", type=Path, help="New output directory (must not already exist)")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--steps", type=int, default=100, help="Navigation actions and maximum distinct browsing files")
    parser.add_argument("--pixels", type=int, default=1600, help="Thumbnail maximum pixel dimension")
    parser.add_argument("--package-cache", type=Path, help="Optional existing Xcode SourcePackages directory for pinned dependencies")
    parser.add_argument("--baseline", type=Path, help="Prior results.json or its containing output directory")
    parser.add_argument("--max-regression-percent", type=float, help="Optional median-time regression gate; requires baseline")
    parser.add_argument("--timeout", type=int, default=3600, help="Build and test timeout in seconds")
    parser.add_argument("--notes", default="", help="Storage, power mode, other applications, and display context")
    parser.add_argument("--validate-only", action="store_true", help="Validate and print catalog manifest without building")
    args = parser.parse_args(argv)
    try:
        if not (1 <= args.runs <= 10 and 1 <= args.steps <= 10000 and 200 <= args.pixels <= 4096 and args.timeout > 0):
            raise ValueError("Use runs 1–10, steps 1–10000, pixels 200–4096, and a positive timeout")
        if args.max_regression_percent is not None and (not args.baseline or not math.isfinite(args.max_regression_percent)
                                                        or args.max_regression_percent < 0):
            raise ValueError("A nonnegative finite regression threshold requires --baseline")
        manifest = catalog_manifest(args.catalog)
        if args.validate_only:
            print(json.dumps(manifest, indent=2))
            return 0
        if platform.system() != "Darwin":
            raise ValueError("This benchmark requires macOS and Xcode")
        baseline = None
        if args.baseline:
            baseline_path = args.baseline / "results.json" if args.baseline.is_dir() else args.baseline
            baseline = json.loads(baseline_path.read_text())
        source = source_identity()
        machine = {"hardware": command_text(["sysctl", "-n", "hw.model"]), "architecture": platform.machine(),
                   "logical_cpus": os.cpu_count(), "memory_bytes": int(command_text(["sysctl", "-n", "hw.memsize"])),
                   "os": platform.mac_ver()[0]}
        settings = {"runs": args.runs, "steps": args.steps, "pixels": args.pixels,
                    "preview_cache_bytes": 256 * 1024 * 1024, "grid_cache_bytes": 128 * 1024 * 1024,
                    "resource_sample_ms": 100, "configuration": "Release", "testability": True, "app_sandbox": False}
        preflight = {"benchmark_version": VERSION, "settings": settings, "machine": machine,
                     "source": source, "catalog": manifest, "summary": {"phases": {}}}
        if baseline:
            compare(preflight, baseline, args.max_regression_percent)
        if args.output:
            output = args.output.expanduser().resolve()
            if output == ROOT or ROOT in output.parents:
                raise ValueError("Keep benchmark output outside the repository to preserve source provenance")
            if output == Path(manifest["directory"]) or Path(manifest["directory"]) in output.parents:
                raise ValueError("Keep benchmark output outside the source catalog")
            output.mkdir(mode=0o700, parents=True, exist_ok=False)
        else:
            output = Path(tempfile.mkdtemp(prefix="rawcull-catalog-performance-"))
        environment = os.environ.copy()
        for name, value in {"RUN": "1", "INPUT": manifest["directory"], "OUTPUT": str(output),
                            "RUNS": str(args.runs), "STEPS": str(args.steps), "PIXELS": str(args.pixels)}.items():
            environment[f"TEST_RUNNER_RAWCULL_CATALOG_PERFORMANCE_{name}"] = value
        # Explicitly disable an inherited opt-in value; Xcode forwards TEST_RUNNER_ variables.
        environment.pop("RAWCULL_CATALOG_PERFORMANCE_RUN", None)
        command = ["xcodebuild", "test", "-project", "RawCull.xcodeproj", "-scheme", "RawCullPerformance",
                   "-destination", f"platform=macOS,arch={platform.machine()}", "-configuration", "Release",
                   "-testPlan", "CatalogPerformance", "-only-testing:RawCullPerformanceTests/CatalogPerformanceTests",
                   "-parallel-testing-enabled", "NO", "-enableCodeCoverage", "NO",
                   "-enableThreadSanitizer", "NO", "-enableAddressSanitizer", "NO",
                   "-onlyUsePackageVersionsFromResolvedFile", "-disableAutomaticPackageResolution",
                   "-resultBundlePath", str(output / "tests.xcresult"),
                   "-derivedDataPath", str(ROOT / "build" / "CatalogPerformance"), "ENABLE_TESTABILITY=YES",
                   "ENABLE_APP_SANDBOX=NO", "CODE_SIGN_ENTITLEMENTS="]
        if args.package_cache:
            command += ["-clonedSourcePackagesDirPath", str(args.package_cache.expanduser().resolve(strict=True))]
        report = {**preflight, "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                  "status": "running", "notes": args.notes, "command": command,
                  "baseline": str(args.baseline.resolve()) if args.baseline else None}
        (output / "run-configuration.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"ARWs: {manifest['file_count']}; runs: {args.runs}; output: {output}", flush=True)
        error = None
        try:
            returncode = run_process(command, environment, output, args.timeout)
        except (TimeoutError, KeyboardInterrupt) as exception:
            returncode = 1
            error = str(exception) or "Interrupted by user"
        report["summary"] = summarize(output, args.runs)
        if returncode:
            report["summary"]["failures"].append(f"xcodebuild exited {returncode}; see xcodebuild.log")
        if error:
            report["summary"]["failures"].append(error)
        try:
            if catalog_manifest(args.catalog) != manifest:
                report["summary"]["failures"].append("Catalog changed while the benchmark was running")
            if source_identity() != source:
                report["summary"]["failures"].append("Source or toolchain changed while the benchmark was running")
        except (OSError, ValueError, subprocess.CalledProcessError) as exception:
            report["summary"]["failures"].append(f"Could not verify final provenance: {exception}")
        if baseline and not report["summary"]["failures"]:
            report["comparison"] = compare(report, baseline, args.max_regression_percent)
            report["resource_comparison"] = compare_resources(report, baseline)
            if any(change["regression"] for change in report["comparison"]):
                report["summary"]["failures"].append("Median timing regression exceeded configured threshold")
        report["status"] = "failed" if report["summary"]["failures"] else "passed"
        report["finished_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        (output / "report.md").write_text(markdown(report))
        print(f"{report['status'].upper()}: {output / 'report.md'}", flush=True)
        return 0 if report["status"] == "passed" else 1
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Catalog benchmark error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
