"""Preparation recovery and complete pagination checks; never launches RawCull."""

import json
from pathlib import Path
import tempfile
import unittest

from PrepareBursts import StopRun, run


class FakeClient:
    def __init__(self, stop_second_page=False):
        self.calls = []
        self.stop_second_page = stop_second_page

    def check_time(self):
        pass

    def pause(self):
        raise StopRun('Interrupted')

    def call(self, name, **arguments):
        self.calls.append((name, arguments))
        if name == 'request_catalog_setup':
            return {'state': 'queued', 'catalogId': 'catalog', 'jobId': 'job'}
        if name == 'get_analysis_status':
            return {'state': 'completed', 'stage': 'completed'}
        if name == 'list_bursts':
            if arguments.get('cursor') == 'page2':
                if self.stop_second_page:
                    raise StopRun('Interrupted during export')
                return {'bursts': [{'id': 'b', 'frameCount': 20}],
                        'coverage': {'burstCount': 2}, 'nextCursor': None}
            return {'bursts': [{'id': 'a', 'frameCount': 3}],
                    'coverage': {'burstCount': 2}, 'nextCursor': 'page2'}
        raise AssertionError(f'Unexpected tool: {name}')


class PrepareBurstsTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / 'results.json'
        self.state = {'catalogPath': '/catalog', 'setupRequestId': 'setup',
                      'sourceJobId': None, 'bursts': [], 'completed': False}

    def test_exports_all_pages_without_assessments(self):
        client = FakeClient()
        run(client, self.path, self.state)
        stored = json.loads(self.path.read_text())
        self.assertEqual([burst['id'] for burst in stored['bursts']], ['a', 'b'])
        self.assertEqual(stored['bursts'][1]['frameCount'], 20)
        self.assertTrue(stored['completed'])
        self.assertEqual(stored['coverage']['burstCount'], 2)
        self.assertEqual({name for name, _ in client.calls},
                         {'request_catalog_setup', 'get_analysis_status', 'list_bursts'})

    def test_resume_keeps_job_and_page_cursor_without_duplicates(self):
        with self.assertRaises(StopRun):
            run(FakeClient(stop_second_page=True), self.path, self.state)
        stored = json.loads(self.path.read_text())
        self.assertEqual(stored['nextCursor'], 'page2')
        client = FakeClient()
        run(client, self.path, stored)
        self.assertEqual([burst['id'] for burst in stored['bursts']], ['a', 'b'])
        self.assertFalse(any(name == 'request_catalog_setup' for name, _ in client.calls))
        calls = [args for name, args in client.calls if name == 'list_bursts']
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]['cursor'], 'page2')
        done = FakeClient()
        run(done, self.path, stored)
        self.assertEqual(done.calls, [])

    def test_lost_setup_response_replays_same_request(self):
        class LostReply(FakeClient):
            def call(self, name, **arguments):
                if name == 'request_catalog_setup':
                    self.submitted = arguments
                    raise RuntimeError('Lost setup reply')
                return super().call(name, **arguments)
        first = LostReply()
        with self.assertRaises(RuntimeError):
            run(first, self.path, self.state)
        second = FakeClient()
        run(second, self.path, self.state)
        self.assertEqual(second.calls[0][1], first.submitted)

    def test_failed_analysis_is_saved_without_export(self):
        class Failed(FakeClient):
            def call(self, name, **arguments):
                if name == 'get_analysis_status':
                    return {'state': 'failed', 'stage': 'scoringSharpness'}
                return super().call(name, **arguments)
        client = Failed()
        with self.assertRaises(RuntimeError):
            run(client, self.path, self.state)
        self.assertEqual(json.loads(self.path.read_text())['analysisStatus']['state'], 'failed')
        self.assertFalse(any(name == 'list_bursts' for name, _ in client.calls))


if __name__ == '__main__':
    unittest.main()
