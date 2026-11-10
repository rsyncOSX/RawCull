#!/usr/bin/env python3
"""Evaluate primary human face sharpness against labeled keeper choices."""

import argparse
import json
import math
from pathlib import Path


POLICY_VERSION = 1
MAX_ADJUSTMENT = 1.5  # In baseline rank positions. Tune on a separate corpus.


def evaluate_burst(burst):
    frames = burst["frames"]
    baseline = [frame["id"] for frame in frames]
    keepers = set(burst["acceptable_keepers"])
    if not baseline or len(set(baseline)) != len(baseline):
        raise ValueError("Each burst needs a nonempty baseline with unique frame IDs")
    if not keepers or not keepers.issubset(baseline):
        raise ValueError("Each burst needs keeper labels drawn from its baseline")

    candidate = baseline
    reason = "unverified_cohort"
    if len(frames) >= 2 and burst.get("verified_primary_human_cohort") is True:
        descriptors = [frame.get("evidence_descriptor") for frame in frames]
        details = [frame.get("local_detail") for frame in frames]
        if not descriptors[0] or any(value != descriptors[0] for value in descriptors):
            reason = "incompatible_evidence"
        elif any(type(value) not in (int, float) or not math.isfinite(value) or value <= 0
                 for value in details):
            reason = "missing_or_invalid_detail"
        else:
            peak = max(details)
            positions = sorted(
                range(len(frames)),
                key=lambda index: index - MAX_ADJUSTMENT * (details[index] / peak),
            )
            candidate = [baseline[index] for index in positions]
            reason = "compared"

    return {
        "id": burst["id"],
        "reason": reason,
        "baseline_order": baseline,
        "candidate_order": candidate,
        "winner_changed": baseline[0] != candidate[0],
        "baseline_hit": baseline[0] in keepers,
        "candidate_hit": candidate[0] in keepers,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        results = [evaluate_burst(burst) for burst in json.loads(args.manifest.read_text())]
        if not results:
            raise ValueError("The manifest needs at least one labeled burst")
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.error(str(error))

    compared = [result for result in results if result["reason"] == "compared"]
    print(json.dumps({
        "policy_version": POLICY_VERSION,
        "burst_count": len(results),
        "compared_count": len(compared),
        "winner_changes": sum(result["winner_changed"] for result in compared),
        "baseline_hits": sum(result["baseline_hit"] for result in compared),
        "candidate_hits": sum(result["candidate_hit"] for result in compared),
        "improvements": sum(result["candidate_hit"] and not result["baseline_hit"] for result in compared),
        "regressions": sum(result["baseline_hit"] and not result["candidate_hit"] for result in compared),
        "bursts": results,
    }, indent=2))


if __name__ == "__main__":
    main()
