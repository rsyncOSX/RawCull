#!/usr/bin/env python3
"""Run the real PhotoAnalysisKit on a folder of photos and compare two revisions."""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import html
import json
import math
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
PIN = ROOT / "RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
EXTENSIONS = set("jpg jpeg heic heif png tif tiff dng cr2 cr3 nef nrw arw raf orf rw2 pef srw webp avif bmp".split())
PRESETS = ("automatic", "birdsAndWildlife", "portrait", "landscape", "generalAction")
QUALITIES = ("fast", "balanced", "highPrecision")
FIELDS = ("file", "category", "burst", "preferred", "calibration", "iso", "aperture", "af_x", "af_y")
VARIANTS = ("combined", "reused", "fresh", "global", "raw")


def run(*command, **options):
    return subprocess.check_output(command, text=True, **options).strip()


def digest(path):
    with path.open("rb") as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
        return result.hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def prompt(label, default=None):
    answer = input(f"{label}{f' [{default}]' if default is not None else ''}: ").strip()
    return answer or default or ""


def path_input(value):
    # Pasting a Finder path can include surrounding shell quotes.
    return Path(value.strip().strip("'\"")).expanduser().resolve()


def pinned_revision():
    for pin in load(PIN)["pins"]:
        if pin["identity"].lower() == "photoanalysiskit":
            return pin["state"]["revision"]
    raise ValueError("PhotoAnalysisKit is missing from RawCull's Package.resolved")


def inventory(catalog):
    if not catalog.is_dir():
        raise ValueError(f"Catalog folder does not exist: {catalog}")
    files = sorted(
        (path for path in catalog.rglob("*")
         if path.is_file() and not path.is_symlink() and path.suffix.lower().lstrip(".") in EXTENSIONS
         and not any(part.startswith(".") for part in path.relative_to(catalog).parts)),
        key=lambda path: path.relative_to(catalog).as_posix(),
    )
    if not files:
        raise ValueError("No supported image files found in the catalog folder")
    return {path.relative_to(catalog).as_posix(): digest(path) for path in files}


def read_labels(path, files):
    if not path:
        return {}
    labels = {}
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or "file" not in reader.fieldnames:
            raise ValueError("Labels CSV must contain a file column")
        for raw in reader:
            row = {field: (raw.get(field) or "").strip() for field in FIELDS}
            name = row["file"]
            if name not in files or name in labels:
                raise ValueError(f"Unknown or duplicate labels CSV path: {name}")
            if row["preferred"] not in ("", "yes", "no") or row["calibration"] not in ("", "yes", "no"):
                raise ValueError(f"Use yes, no, or blank for preferred and calibration: {name}")
            if row["preferred"] and not row["burst"]:
                raise ValueError(f"Preferred labels require a burst ID: {name}")
            if bool(row["af_x"]) != bool(row["af_y"]):
                raise ValueError(f"Provide both normalized AF coordinates: {name}")
            for field in ("aperture", "af_x", "af_y"):
                if row[field]:
                    value = float(row[field])
                    valid = 0 <= value <= 1 if field.startswith("af_") else value > 0
                    if not math.isfinite(value) or not valid:
                        raise ValueError(f"Invalid {field} for {name}")
            if row["iso"] and not 0 < int(row["iso"]) <= 2**31 - 1:
                raise ValueError(f"Invalid ISO for {name}")
            labels[name] = row
    groups = defaultdict(set)
    for row in labels.values():
        if row["burst"] and row["category"]:
            groups[row["burst"]].add(row["category"])
    if any(len(categories) > 1 for categories in groups.values()):
        raise ValueError("Use one category per burst")
    return labels


def prepare_images(files, labels):
    marked = {name for name, label in labels.items() if label["calibration"] == "yes"}
    if not any(label["calibration"] for label in labels.values()):
        # Spread the default sample across the catalog, without using score labels.
        names = list(files)
        count = min(20, len(names))
        marked = {names[index * len(names) // count] for index in range(count)}
    images = []
    for index, (name, sha256) in enumerate(files.items(), 1):
        label = labels.get(name, {})
        images.append({
            "id": f"p{index:04d}", "file": name, "sha256": sha256,
            "category": label.get("category") or "unlabeled", "burst": label.get("burst", ""),
            "preferred": label.get("preferred", ""), "calibration": name in marked,
            "iso": int(label["iso"]) if label.get("iso") else None,
            "aperture": float(label["aperture"]) if label.get("aperture") else None,
            "afX": float(label["af_x"]) if label.get("af_x") else None,
            "afY": float(label["af_y"]) if label.get("af_y") else None,
        })
    return images


def execute_native(repository, revision, manifest, catalog, output):
    with tempfile.TemporaryDirectory(prefix="rawcull-photo-analysis-") as directory:
        temporary = Path(directory)
        kit = temporary / "PhotoAnalysisKit"
        kit.mkdir()
        archive = temporary / "kit.tar"
        subprocess.run(["git", "-C", str(repository), "archive", "--format=tar",
                        "-o", str(archive), revision], check=True)
        subprocess.run(["tar", "-xf", str(archive), "-C", str(kit)], check=True)
        source = temporary / "Sources" / "CatalogRunner"
        source.mkdir(parents=True)
        shutil.copyfile(Path(__file__).with_name("PhotoAnalysisCatalog.swift"), source / "Runner.swift")
        (temporary / "Package.swift").write_text("""// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CatalogEvaluation",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "PhotoAnalysisKit")],
    targets: [.executableTarget(name: "CatalogRunner", dependencies: [
        .product(name: "PhotoAnalysisKit", package: "PhotoAnalysisKit")
    ])]
)
""", encoding="utf-8")
        request = temporary / "request.json"
        save(request, dict(manifest["settings"], images=[
            dict(image, path=str(catalog / image["file"])) for image in manifest["images"]
        ]))
        (output / "images").mkdir()
        subprocess.run(["swift", "run", "--package-path", str(temporary),
                        "-c", "release", "CatalogRunner", str(request), str(output)], check=True)


def breakdown(row, mode="batch"):
    return row.get(mode, {}).get("breakdown", {})


def score(row):
    value = breakdown(row).get("finalScore")
    return value if isinstance(value, (int, float)) and math.isfinite(value) else None


def outcome_counts(values, known):
    counts = Counter(dict.fromkeys(known, 0))
    counts.update(values)
    return dict(counts)


def summarize(manifest, native):
    results = {row["id"]: row for row in native["images"]}
    buckets = defaultdict(list)
    for image in manifest["images"]:
        buckets[None].append(image)
        buckets[image["category"]].append(image)

    summaries = {}
    for category, images in buckets.items():
        rows = [results[image["id"]] for image in images]
        groups = defaultdict(list)
        for image in images:
            if image["burst"]:
                groups[image["burst"]].append(image)
        ranking = Counter(correct=0, wrong=0, tie=0, unavailable=0, unjudged=0)
        winners = {}
        for burst, group in groups.items():
            if len(group) < 2:
                continue
            values = {image["id"]: score(results[image["id"]]) for image in group}
            if any(value is None for value in values.values()):
                winners[burst] = None
            else:
                best = max(values.values())
                winners[burst] = [key for key, value in values.items() if math.isclose(value, best, abs_tol=1e-7)]
            labels = {image["id"]: image["preferred"] for image in group}
            if set(labels.values()) != {"yes", "no"}:
                ranking["unjudged"] += 1
            elif winners[burst] is None:
                ranking["unavailable"] += 1
            elif all(labels[key] == "yes" for key in winners[burst]):
                ranking["correct"] += 1
            elif any(labels[key] == "yes" for key in winners[burst]):
                ranking["tie"] += 1
            else:
                ranking["wrong"] += 1
        summaries["Overall" if category is None else f"Category: {category}"] = {
            "photos": len(images), "ranking": dict(ranking), "winners": winners,
            "decode": dict(Counter(row["status"] for row in rows)),
            "batch": dict(Counter(row["batch"]["status"] for row in rows)),
            "combined": dict(Counter(row.get("combined", {}).get("status", "notRun") for row in rows)),
            "scalar": dict(Counter(row.get("scalar", {}).get("status", "notRun") for row in rows)),
            "focusFailure": outcome_counts(
                (breakdown(row).get("focusFailureKind", "unavailable") for row in rows),
                ("none", "motionBlur", "missedFocus", "unavailable"),
            ),
            "evidenceRegion": outcome_counts(
                ((breakdown(row).get("focusEvidence") or {}).get("winningRegion", "unavailable") for row in rows),
                ("none", "afCenter", "afNeighborhood", "afPoint", "saliency", "global", "mixed", "unavailable"),
            ),
            "maskRegion": outcome_counts(
                (breakdown(row, "combined").get("focusMaskRegionSource") or "unavailable" for row in rows),
                ("none", "saliency", "afPoint", "saliencyAndAF", "unavailable"),
            ),
            "masks": {variant: dict(Counter(
                row.get("masks", {}).get(variant, {}).get("status", "notRun") for row in rows
            )) for variant in VARIANTS},
            "faces": dict(Counter(detector_status(row, "faces") for row in rows)),
            "animals": dict(Counter(detector_status(row, "animals") for row in rows)),
            "featurePrint": dict(Counter(
                row.get("featurePrint", {}).get("status", "notRun") for row in rows
            )),
        }
    return summaries


def detector_status(row, key):
    detector = row.get(key, {})
    if detector.get("status") != "ok":
        return detector.get("status", "notRun")
    values = detector["value"]["faces"] if key == "faces" else detector["value"]
    return "detected" if values else "empty"


def different(before, after):
    """Compare meaningful fields with tolerance for floating-point render noise."""
    if isinstance(before, bool) or isinstance(after, bool):
        return before != after
    if isinstance(before, (float, int)) and isinstance(after, (float, int)):
        return not math.isclose(before, after, rel_tol=1e-6, abs_tol=1e-7)
    if isinstance(before, dict) and isinstance(after, dict):
        return before.keys() != after.keys() or any(different(value, after[key]) for key, value in before.items())
    if isinstance(before, list) and isinstance(after, list):
        return len(before) != len(after) or any(different(a, b) for a, b in zip(before, after))
    return before != after


def report_comparison(root, manifest, before, after, output):
    old_summary = summarize(manifest, before)
    new_summary = summarize(manifest, after)
    old_rows = {row["id"]: row for row in before["images"]}
    new_rows = {row["id"]: row for row in after["images"]}
    old_winners = old_summary["Overall"]["winners"]
    new_winners = new_summary["Overall"]["winners"]
    flips = {burst: {"before": winners, "after": new_winners[burst]}
             for burst, winners in old_winners.items() if winners != new_winners[burst]}
    fields = ("input", "status", "batch", "scalar", "combined", "masks", "faces", "animals", "featurePrint")
    changes = []
    for image in manifest["images"]:
        image_id = image["id"]
        old, new = old_rows[image_id], new_rows[image_id]
        changed = [field for field in fields if different(old.get(field), new.get(field))]
        mask_changes = []
        for variant in VARIANTS:
            a = old.get("masks", {}).get(variant, {})
            b = new.get("masks", {}).get(variant, {})
            if a.get("status") == b.get("status") == "saved":
                if digest(root / "before" / a["file"]) != digest(output / b["file"]):
                    mask_changes.append(variant)
            elif a.get("status") != b.get("status"):
                mask_changes.append(variant)
        changes.append({"id": image_id, "file": image["file"], "category": image["category"],
                        "burst": image["burst"], "changedFields": changed, "changedMaskFiles": mask_changes,
                        "beforeScore": score(old), "afterScore": score(new)})
    comparison = {
        "before": old_summary, "after": new_summary, "burstWinnerChanges": flips,
        "calibration": {"before": before["calibration"], "after": after["calibration"]},
        "batchMilliseconds": {"before": before["batchMilliseconds"], "after": after["batchMilliseconds"]},
        "combinedMedianMilliseconds": {
            phase: statistics.median(times) if (times := [
                row["combinedMilliseconds"] for row in native["images"] if "combinedMilliseconds" in row
            ]) else None
            for phase, native in (("before", before), ("after", after))
        },
        "images": changes,
    }
    save(output / "comparison.json", comparison)
    with (output / "comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["id", "file", "category", "burst", "before_score", "after_score",
                         "before_failure", "after_failure", "changed_fields", "changed_mask_files"])
        for row in changes:
            image_id = row["id"]
            writer.writerow([image_id, row["file"], row["category"], row["burst"],
                             row["beforeScore"], row["afterScore"],
                             breakdown(old_rows[image_id]).get("focusFailureKind"),
                             breakdown(new_rows[image_id]).get("focusFailureKind"),
                             " ".join(row["changedFields"]), " ".join(row["changedMaskFiles"])])
    write_review(output, changes, comparison, old_rows, new_rows)
    print(f"Compared {len(changes)} photos. Burst winner changes: {len(flips)}.")
    print("Overall labeled burst results:", old_summary["Overall"]["ranking"], "→", new_summary["Overall"]["ranking"])


def write_review(output, changes, comparison, old_rows, new_rows):
    escape = html.escape

    def picture(prefix, row):
        preview = row.get("preview")
        if not preview:
            return "<p>No preview</p>"
        mask = row.get("masks", {}).get("combined", {})
        layer = (f'<img class="overlay" alt="" loading="lazy" src="{quote(prefix + mask["file"])}">'
                 if mask.get("status") == "saved" else "")
        return (f'<div class="picture"><img alt="Decoded preview" loading="lazy" '
                f'src="{quote(prefix + preview)}">{layer}</div>')

    lines = ["""<!doctype html><html lang="en"><meta charset="utf-8">
<title>PhotoAnalysisKit before and after</title>
<style>
body{font:16px system-ui;margin:2rem;max-width:1050px} table{border-collapse:collapse}
th,td{padding:.4rem;border-bottom:1px solid #888;text-align:left} section{margin:2rem 0}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:1rem} .picture{position:relative}
img{display:block;width:100%} .overlay{position:absolute;inset:0;height:100%;opacity:.7}
#show:not(:checked) ~ main .overlay{display:none}
</style>
<h1>PhotoAnalysisKit before and after</h1>
<p>Agreement is based on complete burst labels. Unlabeled bursts are still checked for winner changes.
PNG changes compare file bytes. Review the overlays for visual significance.</p>
<table><tr><th>Group</th><th>Photos</th><th>Before burst results</th><th>After burst results</th></tr>"""]
    for category, summary in comparison["before"].items():
        after = comparison["after"][category]
        lines.append(f"<tr><td>{escape(category)}</td><td>{summary['photos']}</td>"
                     f"<td>{escape(str(summary['ranking']))}</td><td>{escape(str(after['ranking']))}</td></tr>")
    lines.extend(['</table><input type="checkbox" id="show" checked><label for="show"> Show focus overlays</label>',
                  "<main><h2>Photo review</h2>"])
    for row in sorted(changes, key=lambda item: (
        item["burst"] not in comparison["burstWinnerChanges"], not bool(item["changedFields"] or item["changedMaskFiles"])
    )):
        image_id = row["id"]
        changed = ", ".join(row["changedFields"] + row["changedMaskFiles"]) or "No recorded changes"
        lines.append(f"<section><h3>{escape(row['file'])}</h3><p>{escape(changed)}</p><div class='pair'>"
                     f"<div>Before · {row['beforeScore']}{picture('../before/', old_rows[image_id])}</div>"
                     f"<div>After · {row['afterScore']}{picture('', new_rows[image_id])}</div></div></section>")
    lines.append("</main></html>")
    (output / "review.html").write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("before", "after"))
    parser.add_argument("--catalog", type=Path, help="Folder containing the image catalog")
    parser.add_argument("--results", type=Path, help="Shared output folder for both runs")
    parser.add_argument("--kit-repo", type=Path, default=ROOT.parent / "PhotoAnalysisKit")
    parser.add_argument("--revision", help="Local PhotoAnalysisKit commit or tag; defaults to RawCull's pin")
    parser.add_argument("--labels", type=Path, help="Optional before-run CSV with category, burst and expected ranking")
    parser.add_argument("--maximum-pixels", type=int)
    parser.add_argument("--preset", choices=PRESETS)
    parser.add_argument("--quality", choices=QUALITIES)
    parser.add_argument("--threshold", type=float)
    parser.add_argument("--make-labels", type=Path, help="Write a labels CSV template and exit")
    args = parser.parse_args()

    if args.make_labels:
        catalog = (args.catalog or path_input(prompt("Image catalog folder"))).resolve()
        with args.make_labels.open("x", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(FIELDS)
            writer.writerows([[name] + [""] * (len(FIELDS) - 1) for name in inventory(catalog)])
        print(f"Labels template: {args.make_labels}")
        return

    phase = args.phase or prompt("Run before or after the update", "before").lower()
    if phase not in ("before", "after"):
        raise ValueError("Enter before or after")
    catalog = (args.catalog or path_input(prompt("Image catalog folder"))).resolve()
    results = (args.results or path_input(prompt("Results folder for both runs", "~/RawCull-PhotoAnalysis-evaluation"))).resolve()
    if results.is_relative_to(catalog):
        raise ValueError("Choose a results folder outside the image catalog")
    target = results / phase
    if target.exists():
        raise ValueError(f"Run already exists: {target}. Choose another results folder to preserve this run.")
    if phase == "after" and not (results / "before" / "manifest.json").is_file():
        raise ValueError("Choose the same results folder used for the before run")

    kit = args.kit_repo.expanduser().resolve()
    pin = pinned_revision()
    reference = args.revision or prompt("PhotoAnalysisKit commit or tag", pin)
    try:
        revision = run("git", "-C", str(kit), "rev-parse", "--verify", f"{reference}^{{commit}}",
                       stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as error:
        raise ValueError(f"Revision {reference} is unavailable in {kit}. Supply a local checkout containing it.") from error

    print("Fingerprinting catalog images…", flush=True)
    files = inventory(catalog)
    runner_hashes = {name: digest(Path(__file__).with_name(name)) for name in
                     ("PhotoAnalysisCatalog.swift", "RunPhotoAnalysisCatalog.py")}
    host = {"macOSBuild": run("sw_vers", "-buildVersion"), "architecture": platform.machine(),
            "swift": run("swift", "--version")}
    requested_settings = {"maximumPixels": args.maximum_pixels, "preset": args.preset,
                          "quality": args.quality, "threshold": args.threshold}
    if phase == "before":
        settings = {"maximumPixels": 1024, "preset": "automatic", "quality": "fast", "threshold": 0.46}
        settings.update({key: value for key, value in requested_settings.items() if value is not None})
        if not 32 <= settings["maximumPixels"] <= 2048 or not 0.01 <= settings["threshold"] <= 0.95:
            raise ValueError("Use a preview size of 32–2048 and a threshold of 0.01–0.95")
        labels = args.labels
        if labels is None and args.phase is None:
            answer = prompt("Optional labels CSV path (Enter to skip)")
            labels = path_input(answer) if answer else None
        images = prepare_images(files, read_labels(labels, files))
    else:
        baseline = load(results / "before" / "manifest.json")
        if baseline["revision"] == revision:
            raise ValueError("Both runs select the same kit revision. Update RawCull's pin or pass --revision.")
        if baseline["host"] != host or baseline["runnerSHA256"] != runner_hashes:
            raise ValueError("Use the same macOS build, Swift toolchain, architecture, and runner as the baseline")
        settings = baseline["settings"]
        if args.labels or any(value is not None and value != settings[key] for key, value in requested_settings.items()):
            raise ValueError("The after run reuses the baseline labels and analysis settings")
        images = baseline["images"]
        original = {image["file"]: image["sha256"] for image in images}
        if original != files:
            differences = [name for name in sorted(original.keys() | files.keys()) if original.get(name) != files.get(name)]
            raise ValueError(f"Catalog differs from the baseline in {len(differences)} file(s): {', '.join(differences[:5])}")
    manifest = {"schema": 1, "phase": phase, "revision": revision, "rawCullPin": pin,
                "host": host, "runnerSHA256": runner_hashes, "settings": settings, "images": images}
    results.mkdir(parents=True, exist_ok=True)
    print(f"Running {phase}: {len(images)} photos on PhotoAnalysisKit {revision[:12]}…", flush=True)
    with tempfile.TemporaryDirectory(dir=results, prefix=f".{phase}-") as stage:
        output = Path(stage) / "run"
        output.mkdir()
        execute_native(kit, revision, manifest, catalog, output)
        if inventory(catalog) != files:
            raise ValueError("Catalog changed during analysis. Rerun with unchanged files.")
        native = load(output / "analysis.json")
        if [row["id"] for row in native["images"]] != [item["id"] for item in images]:
            raise ValueError("Native analysis returned incomplete or out-of-order results")
        save(output / "manifest.json", manifest)
        save(output / "summary.json", summarize(manifest, native))
        if phase == "after":
            report_comparison(results, manifest, load(results / "before" / "analysis.json"), native, output)
        output.rename(target)
    print(f"Saved {target}")
    if phase == "after":
        print(f"Review: {target / 'review.html'}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"PhotoAnalysisKit evaluation: {error}")
    except (EOFError, KeyboardInterrupt):
        sys.exit("PhotoAnalysisKit evaluation stopped.")
