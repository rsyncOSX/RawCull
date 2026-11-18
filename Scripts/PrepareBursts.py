#!/usr/bin/env python3
"""Prepare all catalog bursts: sharpness, similarity, grouping, and ranking.

Python 3.9+, standard library only. Uses RawCull's bundled MCP helper.
No photo assessments are requested. Each exported burst includes the frame count
and the candidates exposed by MCP (currently up to five), not every member photo.
"""

import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import shlex
import time
import uuid

from AssessBursts import MCP, StopRun, heartbeat, save


FORMAT = 'rawcull-burst-preparation'
DEFAULT_HELPER = Path('/Applications/RawCull.app/Contents/MacOS/rawcull-mcp')


def run(client, path, state):
    if state.get('completed'):
        print(f'Already prepared: {len(state["bursts"])} bursts.', flush=True)
        return
    if not state.get('sourceJobId'):
        # The setup request ID is persisted before submission, allowing identical replay.
        setup = client.call('request_catalog_setup', catalogHint=state['catalogPath'],
                            jobType='burstAnalysis', requestId=state['setupRequestId'])
        print('Catalog setup: approve or choose the folder in RawCull if prompted.', flush=True)
        while setup['state'] == 'pendingApproval':
            client.pause()
            setup = heartbeat(client, 'get_catalog_setup_status', requestId=state['setupRequestId'])
        if setup['state'] != 'queued':
            raise RuntimeError(f'Catalog setup did not queue analysis: {setup}')
        state.update(catalogId=setup['catalogId'], sourceJobId=setup['jobId'])
        save(path, state)

    previous = None
    while True:
        status = heartbeat(client, 'get_analysis_status',
                           catalogId=state['catalogId'], jobId=state['sourceJobId'])
        progress = (status.get('state'), status.get('stage'),
                    status.get('stageCompleted'), status.get('stageTotal'))
        if progress != previous:
            print(f'Burst analysis: {progress[0]} ({progress[1]}) '
                  f'— {status.get("filesScanned", 0)} scanned, '
                  f'{status.get("filesAnalyzed", 0)} analyzed', flush=True)
            previous = progress
        state['analysisStatus'] = status
        save(path, state)
        if status['state'] == 'completed':
            break
        if status['state'] not in ('queued', 'running'):
            raise RuntimeError(f'Burst analysis stopped: {status}')
        client.pause()

    # Save each page with its cursor. An interrupted page is replayed, never appended twice.
    seen_cursors = set()
    while True:
        client.check_time()
        arguments = dict(catalogId=state['catalogId'], jobId=state['sourceJobId'], limit=25)
        cursor = state.get('nextCursor')
        if cursor:
            seen_cursors.add(cursor)
            arguments['cursor'] = cursor
        page = heartbeat(client, 'list_bursts', **arguments)
        next_cursor = page.get('nextCursor')
        if next_cursor and next_cursor in seen_cursors:
            raise RuntimeError('RawCull returned a repeated burst cursor.')
        state['bursts'].extend(page['bursts'])
        state['coverage'] = page['coverage']
        state['nextCursor'] = next_cursor
        state['completed'] = not next_cursor
        save(path, state)
        print(f'Exported {len(state["bursts"])} bursts.', flush=True)
        if state['completed']:
            break
    print(f'Preparation complete. Results: {path}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper', type=Path, default=DEFAULT_HELPER)
    parser.add_argument('--catalog', type=Path, help='Catalog folder for a new run')
    parser.add_argument('--output', type=Path, help='New results JSON path; prompts if omitted')
    parser.add_argument('--continue', dest='resume', type=Path, metavar='RESULTS.json',
                        help='Resume an existing file without prompts')
    parser.add_argument('--minutes', type=float, default=0, help='Runtime limit; 0 = unlimited')
    args = parser.parse_args()
    if args.minutes < 0 or not math.isfinite(args.minutes):
        parser.error('--minutes must be a finite nonnegative number')
    if args.resume and (args.catalog or args.output):
        parser.error('--continue cannot be combined with --catalog or --output')
    path = (args.resume or args.output or Path(input(
        'Progress/results JSON path [~/RawCullPreparedBursts.json]: ').strip()
        or '~/RawCullPreparedBursts.json')).expanduser().resolve()
    if args.resume and not path.is_file():
        parser.error(f'Cannot continue: progress file does not exist: {path}')
    if not path.parent.is_dir():
        parser.error('The results parent folder must already exist.')
    helper = args.helper.expanduser().resolve()
    if not helper.is_file() or not os.access(helper, os.X_OK):
        parser.error(f'Missing executable helper: {helper}. Use --helper for another installation.')
    print('Wait until other RawCull clients have finished. New analysis replaces the shared\n'
          'source result and dependent assessments. No photo assessments will be started.\n'
          'Ctrl+C or a time limit leaves admitted work running; resume with the same file.\n')
    with path.with_name(path.name + '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another runner is using this results file.') from None
        if path.exists():
            state = json.loads(path.read_text(encoding='utf-8'))
            if state.get('format') != FORMAT or state.get('formatVersion') != 1:
                raise RuntimeError('Unsupported results format. Choose a new file.')
            if args.catalog and str(args.catalog.expanduser().resolve()) != state['catalogPath']:
                raise RuntimeError('Results belong to another catalog. Choose a new output file.')
            print(f'Resuming catalog: {state["catalogPath"]}', flush=True)
        else:
            catalog = (args.catalog or Path(input('Absolute catalog folder path: ').strip())).expanduser()
            if not catalog.is_absolute() or not catalog.is_dir():
                raise RuntimeError('Enter an existing absolute catalog folder path.')
            state = {'format': FORMAT, 'formatVersion': 1, 'catalogPath': str(catalog.resolve()),
                     'catalogId': None, 'sourceJobId': None, 'setupRequestId': str(uuid.uuid4()),
                     'bursts': [], 'nextCursor': None, 'completed': False,
                     'candidateScope': 'MCP ranked candidates (currently at most five per burst); '
                                       'frameCount includes all burst members.'}
            save(path, state)
        deadline = time.monotonic() + args.minutes * 60 if args.minutes else None
        client = None
        try:
            if not state.get('completed'):
                client = MCP(helper, deadline)
                client.initialize()
                run(client, path, state)
            else:
                print(f'Already prepared: {len(state["bursts"])} bursts. Results: {path}')
        finally:
            if client is not None:
                client.close()
            if not state.get('completed'):
                command = ['python3', str(Path(__file__).resolve()), '--continue', str(path)]
                if helper != DEFAULT_HELPER:
                    command.extend(['--helper', str(helper)])
                print('\nContinue with:\n' + shlex.join(command), flush=True)


if __name__ == '__main__':
    previous_mask = os.umask(0o077)
    try:
        try:
            main()
        except (StopRun, KeyboardInterrupt) as error:
            print(f'\nStopped: {error or "interrupted"}. Resume using the same results file.')
        except (RuntimeError, OSError, ValueError, KeyError, EOFError) as error:
            print(f'\nERROR: {error}')
            raise SystemExit(1)
    finally:
        os.umask(previous_mask)
