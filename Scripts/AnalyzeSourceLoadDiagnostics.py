#!/usr/bin/env python3
"""Attribute adapter latency without treating private parser wait as decode CPU.

Joins diagnostics to containing outer measurements by operation, file and time.
Cancellation journals are deliberately separate from ordinary workload summaries.
"""
import argparse
import json
import math
from pathlib import Path
import statistics
from urllib.parse import unquote, urlparse

OPERATIONS = {"thumbnail.preload": "decode.preload", "thumbnail.interactive": "decode.interactive",
              "preview": "decode.zoomPreview"}
STAMPS = ("submitted", "accessReady", "taskStarted", "parserReturned", "delivered")
STAGES = ("access_ms", "task_schedule_ms", "parser_roundtrip_ms", "delivery_ms")


def analyze(events, threshold_ms=1000):
    metrics = [event for event in events if "milliseconds" in event]
    records = []
    identifiers = set()
    for event in events:
        if event.get("event") != "source-load":
            continue
        timing = event["timing"]
        if timing["id"] in identifiers:
            raise ValueError("Duplicate source-load identifier")
        identifiers.add(timing["id"])
        stamps = [timing[key] for key in STAMPS]
        origin = event["journalOriginUptime"]
        if not all(math.isfinite(value) for value in stamps + [origin]) or stamps != sorted(stamps):
            raise ValueError("Nonfinite or nonmonotonic source-load timestamps")
        source = unquote(urlparse(timing["source"]).path)
        start, end = stamps[0] - origin, stamps[-1] - origin
        matches = [metric for metric in metrics
                   if metric["phase"] == OPERATIONS[timing["operation"]]
                   and metric["detail"] == Path(source).name
                   and metric["elapsedSeconds"] - metric["milliseconds"] / 1000 <= start + 1e-7
                   and end <= metric["elapsedSeconds"] + 1e-7]
        durations = {stage: (right - left) * 1000
                     for stage, left, right in zip(STAGES, stamps, stamps[1:])}
        total = (stamps[-1] - stamps[0]) * 1000
        record = {"id": timing["id"], "source": source, "operation": timing["operation"],
                  "requested_pixels": timing.get("requestedPixelSize"), "start_seconds": start,
                  "end_seconds": end, "adapter_ms": total, **durations,
                  "cancelled": timing["cancelled"], "succeeded": timing["succeeded"],
                  "outer_match_count": len(matches),
                  "outer_ms": matches[0]["milliseconds"] if len(matches) == 1 else None,
                  "dominant_span": max(durations, key=durations.get)}
        if record["outer_ms"] is not None:
            record["outside_adapter_ms"] = record["outer_ms"] - total
        records.append(record)
    ordinary = [r for r in records if not r["cancelled"]]
    return {"count": len(records), "ordinary_count": len(ordinary),
            "cancelled_count": len(records) - len(ordinary),
            "ordinary_failures": sum(not r["succeeded"] for r in ordinary),
            "unmatched_or_ambiguous": sum(r["outer_match_count"] != 1 for r in records),
            "adapter_outliers": [r for r in ordinary if r["adapter_ms"] >= threshold_ms],
            "outer_outliers": [r for r in ordinary if r["outer_ms"] is not None and r["outer_ms"] >= threshold_ms],
            "operations": {operation: {key: statistics.median(r[key] for r in ordinary if r["operation"] == operation)
                                        for key in ("adapter_ms", *STAGES)}
                           for operation in sorted({r["operation"] for r in ordinary})},
            "records": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("benchmark", type=Path)
    parser.add_argument("--threshold-ms", type=float, default=1000)
    args = parser.parse_args()
    if not math.isfinite(args.threshold_ms) or args.threshold_ms < 0:
        parser.error("Threshold must be finite and nonnegative")
    paths = sorted(args.benchmark.glob("run-*/events.jsonl"))
    if not paths:
        parser.error("No run journals found")
    runs, cancellation = {}, {}
    for path in paths:
        runs[path.parent.name] = analyze([json.loads(line) for line in path.read_text().splitlines()], args.threshold_ms)
        cancel = path.with_name("cancellation-events.jsonl")
        if cancel.exists():
            cancellation[path.parent.name] = analyze([json.loads(line) for line in cancel.read_text().splitlines()], args.threshold_ms)
    if not any(run["count"] for run in runs.values()):
        parser.error("No source-load diagnostics; run with --source-diagnostics")
    print(json.dumps({"runs": runs, "cancellation": cancellation,
                     "notes": "Parser roundtrip includes private actor/limiter waits, scheduling, I/O and decode; not CPU time. "
                     "Outer timers additionally include reporting/scheduling. No cross-run syscall attribution."},
                     indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
