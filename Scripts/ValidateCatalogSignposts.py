#!/usr/bin/env python3
"""Validate a single independently exported os-signpost XML table (not modeled intervals)."""
from contextlib import closing
import argparse
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import xml.etree.ElementTree as ET

NAMES = {'CatalogOpen', 'CatalogMetadataScan', 'CatalogThumbnailPreload'}
COMPLETE = 'CatalogThumbnailPreloadComplete'


def catalog_events(path):
    """Keep the XML tree and reference index off the Python heap; retain catalog events only."""
    columns = []
    events = []
    with tempfile.TemporaryDirectory(prefix='rawcull-signposts-') as directory:
        with closing(sqlite3.connect(str(Path(directory) / 'refs.sqlite'))) as refs, path.open('rb') as stream:
            refs.execute('CREATE TABLE refs (id TEXT PRIMARY KEY, value TEXT)')
            parents = []
            cells = []
            for event, element in ET.iterparse(stream, events=('start', 'end')):
                if event == 'start':
                    parents.append(element)
                    if element.tag == 'row':
                        cells = []
                    continue
                if element.tag == 'mnemonic':
                    columns.append(element.text or '')
                value = [element.text or '', element.get('fmt', element.text or '')]
                if element.get('ref'):
                    found = refs.execute('SELECT value FROM refs WHERE id=?', (element.get('ref'),)).fetchone()
                    if found is None:
                        raise ValueError(f"Unresolved signpost reference: {element.get('ref')}")
                    value = json.loads(found[0])
                if element.get('id'):
                    refs.execute('INSERT OR REPLACE INTO refs VALUES (?, ?)', (element.get('id'), json.dumps(value)))
                if len(parents) > 1 and parents[-2].tag == 'row':
                    cells.append(value)
                if element.tag == 'row':
                    if len(columns) != len(cells):
                        raise ValueError('Signpost schema does not match row cells')
                    row = dict(zip(columns, cells))
                    required = {'time', 'process', 'thread', 'scope', 'identifier', 'name',
                                'event-type', 'subsystem', 'category', 'message'}
                    if not required <= row.keys():
                        raise ValueError('Expected a raw os-signpost event schema')
                    if row['subsystem'][0] == 'no.blogspot.RawCull' and row['category'][0] == 'CatalogPerformance':
                        name = row['name'][0]
                        if name in NAMES or name == COMPLETE:
                            events.append({
                                'time_ns': int(row['time'][0]), 'name': name,
                                'kind': row['event-type'][0], 'process': row['process'][1],
                                'scope': row['scope'][0], 'thread': row['thread'][1],
                                'id': row['identifier'][0], 'message': row['message'][1],
                            })
                element.clear()
                parents.pop()
                if parents:
                    parents[-1].remove(element)
    return sorted(events, key=lambda e: e['time_ns'])


def validate(events):
    active = {}
    finished = []
    errors = []
    for event in events:
        name = 'CatalogThumbnailPreload' if event['name'] == COMPLETE else event['name']
        key = (event['process'], event['scope'],
               event['thread'] if event['scope'] == 'Thread' else '', event['id'], name)
        if event['kind'] == 'Begin' and event['name'] in NAMES:
            if key in active:
                errors.append(f'Duplicate Begin: {key}')
            active[key] = {'name': name, 'process': event['process'], 'id': event['id'],
                           'start_ns': event['time_ns'], 'message': event['message'], 'completions': []}
        elif event['name'] == COMPLETE and event['kind'] == 'Event':
            if key not in active:
                errors.append(f'Completion outside preload interval: {key}')
            else:
                active[key]['completions'].append(event)
        elif event['kind'] == 'End' and event['name'] in NAMES:
            interval = active.pop(key, None)
            if interval is None:
                errors.append(f'End without Begin: {key}')
                continue
            interval['end_ns'] = event['time_ns']
            interval['duration_ns'] = event['time_ns'] - interval['start_ns']
            if name == 'CatalogThumbnailPreload':
                completions = interval['completions']
                if len(completions) != 1:
                    errors.append(f'Expected one preload completion: {key}')
                else:
                    message = re.sub(r'(?<=\d)\s+(?=\d)', '', completions[0]['message'])
                    prepared = re.search(r'prepared=(\d+)', message)
                    pixels = re.search(r'pixels=(\d+)', message)
                    start_pixels = re.search(r'pixels=(\d+)', re.sub(r'(?<=\d)\s+(?=\d)', '', interval['message']))
                    if not prepared or not pixels or not start_pixels or pixels[1] != start_pixels[1]:
                        errors.append(f'Missing or inconsistent completion metadata: {key}')
                    else:
                        interval.update(prepared=int(prepared[1]), pixels=int(pixels[1]))
            finished.append(interval)
    errors.extend(f'Unclosed interval: {key}' for key in active)
    missing = NAMES - {i['name'] for i in finished}
    if missing:
        errors.append(f'Missing completed catalog phases: {sorted(missing)}')
    return {'status': 'passed' if not errors else 'failed', 'errors': errors,
            'intervals': finished, 'unfinished': list(active.values()),
            'limit': 'Balanced events do not establish correct UI state, cancellation delivery, or absence of stale callbacks. Partial prepared counts may be valid after cancellation.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xml', type=Path)
    args = parser.parse_args()
    try:
        result = validate(catalog_events(args.xml))
    except (OSError, ValueError, ET.ParseError, sqlite3.Error) as error:
        result = {'status': 'failed', 'errors': [str(error)]}
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
