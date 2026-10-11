#!/usr/bin/env python3
"""Read-only inventory of a local Combined Review export; never copies photographs."""
import argparse
import base64
import hashlib
import json
from pathlib import Path


def freeze(root, run_id):
    files = []
    for path in sorted(root.rglob('*')) if root.is_dir() else []:
        if not path.is_file() or path.suffix.lower() not in {'.json', '.png'}:
            continue
        data = path.read_bytes()
        entry = dict(path=str(path.relative_to(root)), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        if path.suffix.lower() == '.png' and data[:8] == b'\x89PNG\r\n\x1a\n':
            entry['png'] = dict(width=int.from_bytes(data[16:20], 'big'), height=int.from_bytes(data[20:24], 'big'), bitDepth=data[24], colorType=data[25])
        if path.suffix.lower() == '.json':
            envelope = json.loads(data)
            entry['kind'] = envelope.get('kind')
            value = envelope.get('value', {})
            if path.stem.upper() == run_id.upper():
                entry['snapshot'] = value.get('snapshot')
                entry['work'] = value.get('work')
            if envelope.get('kind') == 'stage' and value.get('payload'):
                entry['payload'] = json.loads(base64.b64decode(value['payload']))
        files.append(entry)
    return dict(schemaVersion=1, baselineRunID=run_id, exportAvailable=root.is_dir(), files=files,
                annotationsStatus='pending independent source-space annotation; model bounds are not ground truth')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run-id', default='88E32164-72C2-4943-A55C-F6D2B1AAAE13')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--appearance-root', type=Path)
    args = parser.parse_args()
    result = freeze(args.root, args.run_id)
    if args.appearance_root:
        result['localSources'] = []
        for name in ['DSC00113.ARW', 'DSC00639.ARW', 'DSC02022.ARW', 'DSC05921.ARW', 'DSC09214.ARW', '_DSC6564.ARW']:
            path = args.appearance_root / name
            entry = dict(name=name, available=path.is_file())
            if path.is_file():
                digest = hashlib.sha256()
                with path.open('rb') as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b''):
                        digest.update(chunk)
                entry.update(bytes=path.stat().st_size, sha256=digest.hexdigest())
            result['localSources'].append(entry)
    # Exclusive creation makes accidentally overwriting a frozen inventory an error.
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, sort_keys=True)
        output.write('\n')
