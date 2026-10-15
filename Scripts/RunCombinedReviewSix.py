#!/usr/bin/env python3
"""Run the opt-in full ARW regression once; never edit app code or retry failures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading


def manifest_id(value):
    """Current Swift IDs encode as strings; accept older rawValue envelopes too."""
    return value if isinstance(value, str) else value['rawValue']


def progress_message(output):
    """Read persisted image outcomes; progress never implies test acceptance."""
    try:
        paths = list((output / 'runs').glob('*.json'))
        if not paths:
            return None
        run = json.loads(paths[0].read_text())['value']
        files = sorted(run['snapshot']['files'], key=lambda file: manifest_id(file['id']))
        terminal = {'completed', 'failed', 'skipped'}
        finished = {manifest_id(item['imageID']) for item in run['work']
                    if item['stage'] == 'report' and item['state'] in terminal}
        remaining = [file for file in files if manifest_id(file['id']) not in finished]
        if not remaining:
            return f'Image reviews finished: {len(files)} out of {len(files)}; running comparison and final checks.'
        return f'Running {len(files) - len(remaining) + 1} out of {len(files)}: {remaining[0]["displayName"]}'
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        # A missing/incomplete manifest must not interrupt the actual test.
        return None


def monitor_progress(output, stop):
    previous = None
    while not stop.is_set():
        message = progress_message(output)
        if message and message != previous:
            print(message, flush=True)
            previous = message
        stop.wait(2)

NAMES = ['DSC00639.ARW', 'DSC02022.ARW', '_DSC6564.ARW', 'DSC00113.ARW', 'DSC05921.ARW', 'DSC09214.ARW']


def select_names(directory, frozen=False):
    if frozen:
        return NAMES.copy()
    return sorted(path.name for path in directory.iterdir()
                  if path.is_file() and path.suffix.lower() == '.arw')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True, help='Directory containing input ARW files')
    parser.add_argument('--models', type=Path, default=Path.home() / 'ModelAssets/Release/Models')
    parser.add_argument('--output', type=Path, help='New output directory; default: unique directory in /private/tmp')
    parser.add_argument('--packages', type=Path, help='Existing Swift package cache (optional)')
    parser.add_argument('--frozen', action='store_true', help='Use the original six names and require their frozen hashes')
    parser.add_argument('--preflight-only', action='store_true')
    args = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    if not args.directory.is_dir():
        parser.error(f'Missing directory: {args.directory}')
    names = select_names(args.directory, args.frozen)
    if not names:
        parser.error('At least one ARW file is required in the selected directory.')
    expected = json.loads((repository / 'Docs/CombinedReviewRegression/six-arw-inputs.json').read_text()) if args.frozen else {}
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
        if args.frozen and digest.hexdigest() != expected[name]:
            parser.error(f'RAW differs from frozen fixture: {name}')
    models = {'QWEN': args.models / 'Qwen/qwen3_vl_2b', 'SAM3': args.models / 'SAM3', 'CLIP': args.models / 'CLIP-DataComp'}
    for model in models.values():
        if not model.is_dir():
            parser.error(f'Missing installed model directory: {model}')
    print('Selected ARWs (filename order unless frozen): ' + ', '.join(names), flush=True)
    print('Preflight passed: selected RAW files and installed model directories.', flush=True)
    if args.preflight_only:
        return 0
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='rawcull-six-', dir='/private/tmp')) / 'evidence'
    if output.exists():
        parser.error('Output directory must not exist; previous evidence is never overwritten.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with (output.parent / (output.name + '.inputs.json')).open('x') as manifest:
        json.dump({'frozen': args.frozen, 'directory': str(args.directory.resolve()), 'sha256': inventory}, manifest, indent=2)
    environment = os.environ.copy()
    # Existing probes in this suite stay disabled even if the caller enabled them.
    for key in ['RAWCULL_COMBINED_REVIEW_RUN', 'RAWCULL_COMBINED_SELECTION_RUN']:
        environment[key] = '0'
        environment['TEST_RUNNER_' + key] = '0'
    settings = {'RAWCULL_COMBINED_SIX_RUN': '1', 'RAWCULL_COMBINED_SELECTION_DIRECTORY': str(args.directory.resolve()),
                'RAWCULL_COMBINED_SIX_OUTPUT': str(output), 'RAWCULL_COMBINED_SIX_NAMES': json.dumps(names),
                'RAWCULL_COMBINED_SIX_FROZEN': '1' if args.frozen else '0'}
    settings.update({'RAWCULL_COMBINED_REVIEW_' + key: str(value.resolve()) for key, value in models.items()})
    for key, value in settings.items():
        environment['TEST_RUNNER_' + key] = value
    command = ['xcodebuild', 'test', '-project', 'RawCull.xcodeproj', '-scheme', 'RawCull', '-destination', 'platform=macOS',
               '-onlyUsePackageVersionsFromResolvedFile', '-enableCodeCoverage', 'NO', '-parallel-testing-enabled', 'NO',
               '-only-testing:RawCullTests/CombinedReviewRealModelTests',
               '-derivedDataPath', '/private/tmp/RawCull-evaluation-build', '-resultBundlePath', str(output.parent / (output.name + '.xcresult')),
               'CODE_SIGNING_ALLOWED=NO']
    if args.packages:
        command += ['-clonedSourcePackagesDirPath', str(args.packages.resolve()), '-disableAutomaticPackageResolution']
    print(f'Private evidence: {output}\nTest log: {output.parent / (output.name + ".log")}', flush=True)
    with (output.parent / (output.name + '.log')).open('x') as log:
        print('Building and preparing models; waiting for image reviews to start.', flush=True)
        stop = threading.Event()
        monitor = threading.Thread(target=monitor_progress, args=(output, stop), daemon=True)
        monitor.start()
        try:
            result = subprocess.run(command, cwd=repository, env=environment, stdout=log, stderr=subprocess.STDOUT)
        finally:
            stop.set()
            monitor.join()
    # Missing evidence means the selected test did not execute, even if xcodebuild exited zero.
    if not (output / 'diagnostic.json').is_file():
        print('FAILED: no completed diagnostic; inspect build/test log.', flush=True)
        return result.returncode or 1
    print('Engineering acceptance PASSED; visual qualification remains required.' if result.returncode == 0 else
          'FAILED: acceptance checks did not pass. Evidence retained; no code changed.', flush=True)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
