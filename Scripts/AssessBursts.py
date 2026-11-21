#!/usr/bin/env python3
"""Interactively assess bursts through RawCull's bundled MCP helper, without an LLM client.

Python 3.9+, standard library only. No cloud model or AI subscription is used.
Run only when another client is no longer using RawCull's analysis worker.
"""

import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import queue
import shlex
import subprocess
import threading
import time
import uuid


class StopRun(Exception):
    pass


class MCPBusyError(RuntimeError):
    pass


class MCP:
    """Minimal newline-delimited JSON-RPC stdio client for the bundled helper."""

    def __init__(self, helper, deadline):
        self.deadline = deadline
        self.sequence = 0
        self.messages = queue.Queue()
        self.process = subprocess.Popen(
            [str(helper)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=None, text=True, encoding='utf-8', bufsize=1)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            for line in self.process.stdout:
                self.messages.put(json.loads(line))
        except Exception as error:
            self.messages.put(error)
        finally:
            self.messages.put(EOFError('RawCull MCP helper disconnected.'))

    def check_time(self):
        if self.deadline is not None and time.monotonic() >= self.deadline:
            raise StopRun('Time limit reached.')

    def send(self, message):
        self.check_time()
        self.process.stdin.write(json.dumps({'jsonrpc': '2.0', **message}) + '\n')
        self.process.stdin.flush()

    def request(self, method, params):
        self.sequence += 1
        request_id = self.sequence
        self.send({'id': request_id, 'method': method, 'params': params})
        timeout = time.monotonic() + 60
        while True:
            self.check_time()
            if time.monotonic() >= timeout:
                raise RuntimeError(f'MCP response timed out: {method}. Resume with the same progress file.')
            try:
                message = self.messages.get(timeout=0.2)
            except queue.Empty:
                continue
            if isinstance(message, Exception):
                raise message
            if message.get('id') == request_id:
                if 'error' in message:
                    raise RuntimeError(json.dumps(message['error']))
                return message['result']
            if 'method' in message and 'id' in message:
                if message['method'] == 'ping':
                    self.send({'id': message['id'], 'result': {}})
                else:
                    self.send({'id': message['id'], 'error': {
                        'code': -32601, 'message': 'Client method not supported'}})

    def initialize(self):
        self.request('initialize', {
            'protocolVersion': '2025-03-26', 'capabilities': {},
            'clientInfo': {'name': 'rawcull-burst-script', 'version': '1.0'}})
        self.send({'method': 'notifications/initialized'})

    def call(self, name, **arguments):
        reply = self.request('tools/call', {'name': name, 'arguments': arguments})
        if reply.get('isError'):
            structured = reply.get('structuredContent')
            if isinstance(structured, dict) and structured.get('errorCode') == 'busy':
                raise MCPBusyError(f'{name}: {json.dumps(reply, ensure_ascii=False)}')
            raise RuntimeError(f'{name}: {json.dumps(reply, ensure_ascii=False)}')
        value = reply.get('structuredContent')
        if not isinstance(value, dict):
            raise RuntimeError(f'{name}: expected structuredContent, received {reply!r}')
        return value

    def pause(self):
        for _ in range(10):
            self.check_time()
            time.sleep(0.2)

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.process.stdout.close()


def heartbeat(client, method, patience=30, **arguments):
    """Call an idempotent endpoint, tolerating the helper's transient storage lock."""
    deadline = time.monotonic() + patience
    delay = 0.5
    while True:
        try:
            return client.call(method, **arguments)
        except MCPBusyError:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(f'{method}: assessment storage remained busy for {patience} seconds.') from None
            client.check_time()
            time.sleep(min(delay, remaining))
            delay = min(delay * 2, 5)


def save(path, state):
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        json.dump(state, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def number(prompt, integer=False):
    while True:
        text = input(prompt).strip() or '0'
        try:
            value = int(text) if integer else float(text)
            if value >= 0 and math.isfinite(value):
                return value
        except ValueError:
            pass
        print('Enter a nonnegative number (0 means no limit).')


def run(client, path, state, limit):
    # Persist setup identity before any submission. An interrupted setup is replayed.
    if not state.get('sourceJobId'):
        setup = client.call('request_catalog_setup', catalogHint=state['catalogPath'],
                            jobType='burstAnalysis', requestId=state['setupRequestId'])
        print('Catalog setup: approve or choose the folder in RawCull if prompted.', flush=True)
        while setup['state'] == 'pendingApproval':
            client.pause()
            setup = heartbeat(client, 'get_catalog_setup_status',
                              requestId=state['setupRequestId'])
        if setup['state'] != 'queued':
            raise RuntimeError(f'Catalog setup did not queue analysis: {setup}')
        state.update(catalogId=setup['catalogId'], sourceJobId=setup['jobId'])
        save(path, state)

    previous = None
    while True:
        status = heartbeat(client, 'get_analysis_status',
                           catalogId=state['catalogId'], jobId=state['sourceJobId'])
        message = (status.get('state'), status.get('stage'))
        if message != previous:
            print(f'Burst analysis: {message[0]} ({message[1]})', flush=True)
            previous = message
        if status['state'] == 'completed':
            break
        if status['state'] not in ('queued', 'running'):
            raise RuntimeError(f'Burst analysis stopped: {status}')
        client.pause()

    if state.get('bursts') is None:
        bursts, cursor = [], None
        while True:
            arguments = dict(catalogId=state['catalogId'], jobId=state['sourceJobId'], limit=25)
            if cursor:
                arguments['cursor'] = cursor
            page = client.call('list_bursts', **arguments)
            bursts.extend(page['bursts'])
            cursor = page.get('nextCursor')
            if not cursor:
                break
        state['bursts'] = bursts
        save(path, state)

    processed = 0
    for index, burst in enumerate(state['bursts'], 1):
        client.check_time()
        entry = state['assessments'].get(burst['id'])
        if entry and entry.get('finished'):
            continue
        if limit and processed >= limit:
            raise StopRun('Burst limit reached for this invocation.')
        if entry is None:
            entry = {'requestId': str(uuid.uuid4()), 'finished': False}
            state['assessments'][burst['id']] = entry
            save(path, state)
        print(f'Burst {index}/{len(state["bursts"])}: {burst["id"]}', flush=True)
        arguments = dict(catalogId=state['catalogId'], sourceJobId=state['sourceJobId'],
                         burstId=burst['id'], rubric=state['rubric'], requestId=entry['requestId'])
        # Identical replay recovers admission if the prior process lost its response.
        # RawCull holds the worker lease briefly after publishing the previous result,
        # and a foreign pending request blocks admission for up to 120 seconds, so
        # a busy reply here is retried with the same request ID.
        status = heartbeat(client, 'start_photo_assessment', patience=150, **arguments)
        while status['state'] in ('queued', 'running'):
            client.pause()
            status = heartbeat(client, 'get_photo_assessment_status',
                               requestId=entry['requestId'])
        entry['status'] = status
        save(path, state)
        if status['state'] in ('completed', 'failed'):
            # Failed requests may still carry useful per-photo failure evidence.
            entry['result'] = heartbeat(client, 'get_photo_assessment_result',
                                        requestId=entry['requestId'])
        entry['finished'] = True
        save(path, state)
        processed += 1
        result = entry.get('result', {})
        print(f'  {status["state"]}: {result.get("assessedCount", 0)} assessed, '
              f'{result.get("failedCount", 0)} failed', flush=True)
        if status['state'] != 'completed':
            raise RuntimeError('Assessment stopped. Its status was saved; inspect it before continuing.')
    print('All selected bursts have been processed.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper', type=Path,
                        default=Path('/Applications/RawCull.app/Contents/MacOS/rawcull-mcp'))
    parser.add_argument('--continue', dest='resume', type=Path, metavar='RESULTS.json',
                        help='Resume an existing progress file without interactive prompts')
    parser.add_argument('--max-bursts', type=int, help='Additional bursts this invocation; 0 = all')
    parser.add_argument('--minutes', type=float, help='Runtime limit this invocation; 0 = unlimited')
    args = parser.parse_args()
    if args.max_bursts is not None and args.max_bursts < 0:
        parser.error('--max-bursts must be nonnegative')
    if args.minutes is not None and (args.minutes < 0 or not math.isfinite(args.minutes)):
        parser.error('--minutes must be a finite nonnegative number')
    print('Run this only after Copilot or other RawCull clients have finished.\n'
          'Results contain local model findings, which may be inaccurate.\n'
          'A time limit or Ctrl+C leaves admitted RawCull work running; resume with the same file.\n')
    path = (args.resume or Path(input('Progress/results JSON path [~/RawCullBurstResults.json]: ').strip()
                or '~/RawCullBurstResults.json')).expanduser().resolve()
    if args.resume and not path.is_file():
        parser.error(f'Cannot continue: progress file does not exist: {path}')
    if not path.parent.is_dir():
        raise RuntimeError('The parent folder for the progress file must already exist.')
    if not args.helper.is_file() or not os.access(args.helper, os.X_OK):
        raise RuntimeError(f'Missing executable helper: {args.helper}. Use --helper for another app location.')
    # Keep one runner per results file. The separate lock survives atomic JSON replacement.
    with path.with_name(path.name + '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another runner is using this progress file.') from None
        if path.exists():
            state = json.loads(path.read_text(encoding='utf-8'))
            if state.get('formatVersion') != 1:
                raise RuntimeError('Unsupported progress file format. Choose a new file.')
            print(f'Resuming catalog: {state["catalogPath"]}')
        else:
            catalog = Path(input('Absolute catalog folder path: ').strip()).expanduser()
            if not catalog.is_absolute() or not catalog.is_dir():
                raise RuntimeError('Enter an existing absolute catalog folder path.')
            print('To reuse completed burst analysis, supply BOTH IDs from its MCP log.\n'
                  'Leave both blank to request a NEW analysis (replaces the shared source result).')
            catalog_id = input('Existing catalog ID [new analysis]: ').strip()
            job_id = input('Existing completed source job ID [new analysis]: ').strip()
            if bool(catalog_id) != bool(job_id):
                raise RuntimeError('Supply both IDs or leave both blank.')
            if catalog_id:
                catalog_id, job_id = str(uuid.UUID(catalog_id)), str(uuid.UUID(job_id))
            state = {'formatVersion': 1, 'catalogPath': str(catalog.resolve()),
                     'catalogId': catalog_id or None, 'sourceJobId': job_id or None,
                     'setupRequestId': str(uuid.uuid4()), 'bursts': None, 'assessments': {},
                     'rubric': ['composition', 'exposure', 'subjectVisibility']}
            save(path, state)
        limit = args.max_bursts
        if limit is None:
            limit = 0 if args.resume else number('Maximum additional bursts this run [0 = all]: ', integer=True)
        minutes = args.minutes
        if minutes is None:
            minutes = 0 if args.resume else number('Maximum minutes, including setup/analysis [0 = unlimited]: ')
        print(f'Progress and results: {path}', flush=True)
        deadline = time.monotonic() + minutes * 60 if minutes else None
        client = None
        try:
            client = MCP(args.helper, deadline)
            client.initialize()
            run(client, path, state, limit)
        finally:
            if client is not None:
                client.close()
            command = ['python3', str(Path(__file__).resolve()), '--continue', str(path)]
            if args.helper != Path('/Applications/RawCull.app/Contents/MacOS/rawcull-mcp'):
                command.extend(['--helper', str(args.helper)])
            print('\nContinue later with:\n' + shlex.join(command), flush=True)


if __name__ == '__main__':
    previous_mask = os.umask(0o077)
    try:
        try:
            main()
        except (StopRun, KeyboardInterrupt) as error:
            print(f'\nStopped: {error or "interrupted"}. Resume using the same progress file.')
        except (RuntimeError, OSError, ValueError, KeyError, EOFError) as error:
            print(f'\nERROR: {error}')
            raise SystemExit(1)
    finally:
        os.umask(previous_mask)
