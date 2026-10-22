#!/usr/bin/env python3
"""Score exported AF crops and evaluate explicitly labeled within-burst pairs."""
import argparse
import csv
import html
import json
import math
from pathlib import Path

METHODS = ("rawcull", "laplacian", "tenengrad")


def evaluate(scores, pairs):
    totals = {m: dict(correct=0, wrong=0, model_tie=0, unavailable=0) for m in METHODS}
    seen = set()
    judged = ties = uncertain = pending = 0
    for row in pairs:
        a, b = row["a"], row["b"]
        if a == b or a not in scores or b not in scores:
            raise ValueError(f"Invalid pair: {a}, {b}")
        key = tuple(sorted((a, b)))
        if key in seen:
            raise ValueError(f"Duplicate pair: {a}, {b}")
        seen.add(key)
        if not row.get("burst", "").strip():
            raise ValueError(f"Pair needs an explicit burst ID: {a}, {b}")
        label = row["label"].strip().upper()
        if label not in ("", "A", "B", "TIE", "UNCERTAIN"):
            raise ValueError(f"Invalid label: {label}")
        if label == "":
            pending += 1
            continue
        if label == "TIE":
            ties += 1
            continue
        if label == "UNCERTAIN":
            uncertain += 1
            continue
        judged += 1
        for method in METHODS:
            x, y = scores[a].get(method), scores[b].get(method)
            if x is None or y is None or not all(math.isfinite(v) and v >= 0 for v in (x, y)):
                outcome = "unavailable"
            elif x == y:
                outcome = "model_tie"
            else:
                outcome = "correct" if ((x > y) == (label == "A")) else "wrong"
            totals[method][outcome] += 1
    return dict(judged=judged, photographer_ties=ties, uncertain=uncertain, pending=pending, methods=totals)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--pairs", type=Path, help="CSV columns: burst,a,b,label; labels A/B/tie/uncertain")
    args = parser.parse_args()
    import cv2
    import numpy as np

    manifest = json.loads((args.dataset / "manifest.json").read_text())
    if manifest.get("schema") != 1 or not manifest.get("complete"):
        raise ValueError("Requires a complete schema-1 export")
    scores = {}
    for item in manifest["images"]:
        values = {}
        if "crop" in item:
            image = cv2.imread(str(args.dataset / item["crop"]), cv2.IMREAD_COLOR)
            if image is None:
                raise ValueError(f"Unreadable crop: {item['crop']}")
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float64)
            # Article's defaults: ksize=1 Laplacian and ksize=3 Sobel.
            # Reflect-101 avoids artificial zero-padding edges; no resizing/denoising.
            lap = cv2.Laplacian(gray, cv2.CV_64F, ksize=1, borderType=cv2.BORDER_REFLECT_101)
            gx = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3, borderType=cv2.BORDER_REFLECT_101)
            gy = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3, borderType=cv2.BORDER_REFLECT_101)
            values = dict(rawcull=item["rawcull"], laplacian=float(np.var(lap)),
                          tenengrad=float(np.mean(np.hypot(gx, gy))))
        if item["id"] in scores:
            raise ValueError("Duplicate image ID")
        scores[item["id"]] = values
    (args.dataset / "scores.json").write_text(json.dumps(dict(
        opencv=cv2.__version__, numpy=np.__version__, scenario=manifest["scenario"], scores=scores), indent=2))

    if args.pairs:
        with args.pairs.open(newline="") as stream:
            pairs = list(csv.DictReader(stream))
        result = evaluate(scores, pairs)
        lines = ["# AF sharpness pair agreement", "", f"Decisive photographer pairs: {result['judged']}",
                 f"Photographer ties: {result['photographer_ties']}; uncertain: {result['uncertain']}; pending: {result['pending']}",
                 "", "| Method | Correct | Wrong | Model tie | Unavailable | Agreement on available decisive pairs |",
                 "|---|---:|---:|---:|---:|---:|"]
        for method, counts in result["methods"].items():
            n = counts["correct"] + counts["wrong"] + counts["model_tie"]
            rate = f"{counts['correct']/n:.1%}" if n else "unavailable"
            lines.append(f"| {method} | {counts['correct']} | {counts['wrong']} | {counts['model_tie']} | {counts['unavailable']} | {rate} |")
        lines += ["", "Model ties count as non-agreement. Photographer ties and uncertain labels are excluded.",
                  "Pairs within a burst are correlated; these are descriptive results, not independent-sample significance tests.",
                  "Compare coverage as well as agreement. Use held-out bursts before tuning or claiming improvement."]
        (args.dataset / "agreement.md").write_text("\n".join(lines) + "\n")
        (args.dataset / "agreement.json").write_text(json.dumps(result, indent=2))
        print("\n".join(lines))

    # A review page contains only pair IDs and crops, never scores or filenames.
    # Caller explicitly chooses burst membership; do not infer it from filename order.
    pairs_path = args.dataset / "pairs-template.csv"
    if not pairs_path.exists():
        pairs_path.write_text("burst,a,b,label\n")
    review_pairs = pairs if args.pairs else []
    page = ["<!doctype html><meta charset='utf-8'><title>AF pair review</title>",
            "<style>body{font:18px system-ui;background:#222;color:#eee}img{image-rendering:pixelated;width:320px;max-width:45vw}section{margin:2em}</style>",
            "<h1>AF pair review</h1><p>Judge intended subject detail. Enter A, B, tie, or uncertain in your pairs CSV before opening scores.</p>"]
    by_id = {item["id"]: item for item in manifest["images"]}
    if not review_pairs:
        page.append("<p>Choose pairs from the same burst in pairs.csv, then rerun with --pairs. Crop inventory:</p>")
        for item in manifest["images"]:
            crop = item.get("crop")
            label = html.escape(item["id"])
            page.append(f"<section><h2>{label}</h2><img src='{html.escape(crop, quote=True)}'></section>"
                        if crop else f"<section><h2>{label}</h2>Unavailable</section>")
    for pair in review_pairs:
        page.append(f"<section><h2>{html.escape(pair['burst'])}: {html.escape(pair['a'])} / {html.escape(pair['b'])}</h2>")
        for side in ("a", "b"):
            crop = by_id[pair[side]].get("crop")
            page.append(f"<span>{side.upper()} <img src='{html.escape(crop, quote=True)}'></span>" if crop else "<span>Unavailable</span>")
        page.append("</section>")
    (args.dataset / "review.html").write_text("\n".join(page))


if __name__ == "__main__":
    main()
