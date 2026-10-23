#!/usr/bin/env python3
"""Run SAM 3 + CLIP, Qwen Vision and Objects sequentially with private diagnostics."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading


def progress_message(output):
    try:
        rows = json.loads((output / 'progress.json').read_text())
        return f"Finished {len(rows)} analyses; last: {rows[-1]['stage']} {rows[-1]['file']}"
    except (OSError, ValueError, IndexError, KeyError, TypeError):
        return None


def monitor_progress(output, stop):
    previous = None
    while not stop.is_set():
        message = progress_message(output)
        if message and message != previous:
            print(message, flush=True)
            previous = message
        stop.wait(2)


def select_names(directory, limit=None):
    return sorted(path.name for path in directory.iterdir()
                  if path.is_file() and path.suffix.lower() == '.arw')[:limit]


def _main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True, help='Directory containing input ARW files')
    parser.add_argument('--models', type=Path, default=Path.home() / 'ModelAssets/Release/Models')
    parser.add_argument('--output', type=Path, help='New output directory; default: unique directory in /private/tmp')
    parser.add_argument('--packages', type=Path, help='Existing Swift package cache (optional)')
    parser.add_argument('--limit', type=int, help='Maximum ARW files (default: all files)')
    parser.add_argument('--preflight-only', action='store_true')
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error('--limit must be a positive integer.')
    repository = Path(__file__).resolve().parent.parent
    if not args.directory.is_dir():
        parser.error(f'Missing directory: {args.directory}')
    names = select_names(args.directory, args.limit)
    if not names:
        parser.error('At least one ARW file is required in the selected directory.')
    inventory = {}
    for name in names:
        source = args.directory / name
        if not source.is_file():
            parser.error(f'Missing RAW: {source}')
        digest = hashlib.sha256()
        with source.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        inventory[name] = digest.hexdigest()
    models = {'QWEN': args.models / 'Qwen/qwen3_vl_2b', 'SAM3': args.models / 'SAM3', 'CLIP': args.models / 'CLIP-DataComp'}
    for model in models.values():
        if not model.is_dir():
            parser.error(f'Missing installed model directory: {model}')
    print('Selected ARWs (filename order): ' + ', '.join(names), flush=True)
    print('Preflight passed: selected RAW files and installed model directories.', flush=True)
    if args.preflight_only:
        return 0
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='rawcull-analysis-', dir='/private/tmp')) / 'evidence'
    if output.exists():
        parser.error('Output directory must not exist; previous evidence is never overwritten.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with (output.parent / (output.name + '.inputs.json')).open('x') as manifest:
        json.dump({'limit': args.limit, 'directory': str(args.directory.resolve()), 'sha256': inventory}, manifest, indent=2)
    environment = os.environ.copy()
    # Existing probes in this suite stay disabled even if the caller enabled them.
    for key in ['RAWCULL_COMBINED_REVIEW_RUN', 'RAWCULL_COMBINED_SELECTION_RUN', 'RAWCULL_COMBINED_SIX_RUN']:
        environment[key] = '0'
        environment['TEST_RUNNER_' + key] = '0'
    for key in ['OBJECT_PROBE_IMAGE', 'QWEN_PHASE3_IMAGE']:
        environment.pop(key, None)
        environment.pop('TEST_RUNNER_' + key, None)
    settings = {'RAWCULL_ANALYSIS_RUN': '1', 'RAWCULL_ANALYSIS_DIRECTORY': str(args.directory.resolve()),
                'RAWCULL_ANALYSIS_OUTPUT': str(output), 'RAWCULL_ANALYSIS_NAMES': json.dumps(names)}
    settings.update({'RAWCULL_ANALYSIS_' + key: str(value.resolve()) for key, value in models.items()})
    for key, value in settings.items():
        environment['TEST_RUNNER_' + key] = value
    command = ['xcodebuild', 'test', '-project', 'RawCull.xcodeproj', '-scheme', 'RawCull', '-destination', 'platform=macOS',
               '-onlyUsePackageVersionsFromResolvedFile', '-enableCodeCoverage', 'NO', '-parallel-testing-enabled', 'NO',
               '-only-testing:RawCullTests/AIAnalysisRealModelTests',
               '-derivedDataPath', '/private/tmp/RawCull-evaluation-build', '-resultBundlePath', str(output.parent / (output.name + '.xcresult')),
               'CODE_SIGNING_ALLOWED=NO']
    if args.packages:
        command += ['-clonedSourcePackagesDirPath', str(args.packages.resolve()), '-disableAutomaticPackageResolution']
    print(f'Private evidence: {output}\nTest log: {output.parent / (output.name + ".log")}', flush=True)
    with (output.parent / (output.name + '.log')).open('x') as log:
        print('Building and preparing models; analysis order: SAM 3 + CLIP, Qwen Vision, Objects.', flush=True)
        stop = threading.Event()
        monitor = threading.Thread(target=monitor_progress, args=(output, stop), daemon=True)
        monitor.start()
        try:
            result = subprocess.run(command, cwd=repository, env=environment, stdout=log, stderr=subprocess.STDOUT)
        finally:
            stop.set()
            monitor.join()
    final_progress = progress_message(output)
    if final_progress:
        print('Final progress: ' + final_progress, flush=True)
    # Missing evidence means the selected test did not execute, even if xcodebuild exited zero.
    if not (output / 'diagnostic.json').is_file():
        print('FAILED: no completed diagnostic; inspect build/test log.', flush=True)
        return result.returncode or 1
    print('All analysis probes PASSED; inspect diagnostics for model behavior.' if result.returncode == 0 else
          'FAILED: analysis probes reported failures. Evidence retained.', flush=True)
    return result.returncode


def main():
    # Evidence can contain private photographs. Restore the caller's process mask
    # even on preflight errors, so calling this runner has no lasting side effect.
    previous_mask = os.umask(0o077)
    try:
        return _main()
    finally:
        os.umask(previous_mask)


if __name__ == '__main__':
    raise SystemExit(main())
