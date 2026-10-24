#!/usr/bin/env python3
"""Split version-2 grid measurements using each run's completed preload intervals.

Summed durations can overlap; they are neither phase wall time nor CPU time.
Metrics crossing a boundary are explicitly unassigned rather than guessed.
"""
import argparse
import json
from pathlib import Path
import statistics

PHASES = ("preload.emptyDiskCache", "preload.warmDiskCache",
          "preload.withBrowsing", "preload.recovery")


def analyze(metrics):
    windows = {}
    for phase in PHASES:
        matches = [metric for metric in metrics if metric["phase"] == phase]
        if len(matches) != 1:
            raise ValueError(f"Expected one completed {phase} interval, got {len(matches)}")
        metric = matches[0]
        end = metric["elapsedSeconds"]
        duration = metric["milliseconds"] / 1000
        if duration < 0 or not metric["succeeded"]:
            raise ValueError(f"Invalid or failed {phase} interval")
        windows[phase] = (end - duration, end, metric["milliseconds"])
    groups = {phase: [] for phase in PHASES}
    unassigned = []
    for metric in metrics:
        if metric["phase"] != "grid.preloadResize":
            continue
        end = metric["elapsedSeconds"]
        start = end - metric["milliseconds"] / 1000
        matches = [phase for phase, (lower, upper, _) in windows.items()
                   if lower <= start <= end <= upper]
        if len(matches) == 1:
            groups[matches[0]].append(metric)
        else:
            unassigned.append(metric)
    summary = {}
    for phase, group in groups.items():
        times = [metric["milliseconds"] for metric in group]
        summary[phase] = {
            "wall_ms": windows[phase][2], "grid_count": len(times),
            "grid_failed": sum(not metric["succeeded"] for metric in group),
            "grid_sum_ms": sum(times),
            "grid_median_ms": statistics.median(times) if times else None,
        }
    return {"phases": summary, "unassigned_grid_count": len(unassigned)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("benchmark", type=Path)
    args = parser.parse_args()
    paths = sorted(args.benchmark.glob("run-*/results.json"))
    if not paths:
        parser.error("No run-*/results.json found")
    result = {path.parent.name: analyze(json.loads(path.read_text())["metrics"]) for path in paths}
    print(json.dumps({"runs": result, "notes":
                     "Grid durations include any lazy decode triggered by drawing. Sums may overlap; not CPU time. "
                     "RAM is cleared between these benchmark passes; counts do not imply app cache misses."},
                     indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
