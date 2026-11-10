#!/usr/bin/env python3
"""Evaluate primary human face sharpness against labeled keeper choices."""

import argparse
import json
import math
from pathlib import Path


PRIMARY_POLICY_VERSION = 1
GROUP_POLICY_VERSION = 1
MAX_ADJUSTMENT = 1.5  # In baseline rank positions. Tune on a separate corpus.


def usable_detail(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def group_details(burst, frames):
    # Track IDs are assigned by the labeler. Vision observation IDs are frame-local.
    cohort = burst.get("relevant_human_face_ids", [])
    if (burst.get("verified_group_human_cohort") is not True
            or not isinstance(cohort, list)
            or len(cohort) < 2
            or any(not isinstance(face, str) or not face for face in cohort)
            or len(set(cohort)) != len(cohort)):
        return None
    details = []
    for frame in frames:
        faces = frame.get("face_details")
        if (not isinstance(faces, dict)
                or faces.keys() != set(cohort)
                or not all(usable_detail(value) for value in faces.values())):
            return None
        details.append(faces)

    # Normalize within each person before comparing the least sharp relevant face.
    peaks = {face: max(frame[face] for frame in details) for face in cohort}
    return [min(frame[face] / peaks[face] for face in cohort) for frame in details]


def evaluate_burst(burst, *, group=False):
    frames = burst["frames"]
    baseline = [frame["id"] for frame in frames]
    keepers = set(burst["acceptable_keepers"])
    if not baseline or len(set(baseline)) != len(baseline):
        raise ValueError("Each burst needs a nonempty baseline with unique frame IDs")
    if not keepers or not keepers.issubset(baseline):
        raise ValueError("Each burst needs keeper labels drawn from its baseline")

    candidate = baseline
    reason = "unverified_cohort"
    if len(frames) >= 2:
        if group:
            details = group_details(burst, frames)
            if details is None:
                reason = "unverified_or_incomplete_group_cohort"
        else:
            details = ([frame.get("local_detail") for frame in frames]
                       if burst.get("verified_primary_human_cohort") is True else None)

        if details is not None:
            descriptors = [frame.get("evidence_descriptor") for frame in frames]
            if not descriptors[0] or any(value != descriptors[0] for value in descriptors):
                reason = "incompatible_evidence"
            elif not all(usable_detail(value) for value in details):
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
    parser.add_argument("--group", action="store_true", help="Evaluate manually associated groups offline")
    args = parser.parse_args()
    try:
        results = [evaluate_burst(burst, group=args.group) for burst in json.loads(args.manifest.read_text())]
        if not results:
            raise ValueError("The manifest needs at least one labeled burst")
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.error(str(error))

    compared = [result for result in results if result["reason"] == "compared"]
    print(json.dumps({
        "policy_version": GROUP_POLICY_VERSION if args.group else PRIMARY_POLICY_VERSION,
        **({"mode": "group"} if args.group else {}),
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
