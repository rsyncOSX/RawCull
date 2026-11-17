"""Runner recovery checks using a fake MCP client; never starts RawCull."""

import copy
import json
from pathlib import Path
import tempfile
import unittest

from AssessBursts import StopRun, run


class FakeClient:
    def __init__(self, interrupt=False):
        self.calls = []
        self.interrupt = interrupt

    def check_time(self):
        pass

    def pause(self):
        raise StopRun('Simulated time limit')

    def call(self, name, **arguments):
        self.calls.append((name, arguments))
        if name == 'get_analysis_status':
            return {'state': 'completed', 'stage': 'completed'}
        if name == 'start_photo_assessment':
            return {'state': 'running' if self.interrupt else 'completed'}
        if name == 'get_photo_assessment_result':
            return {'assessedCount': 2, 'failedCount': 0}
        raise AssertionError(f'Unexpected call: {name}')


class AssessBurstsTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / 'progress.json'
        self.state = {'sourceJobId': 'source', 'catalogId': 'catalog',
                      'rubric': ['exposure'], 'bursts': [{'id': 'a'}, {'id': 'b'}],
                      'assessments': {}}

    def test_interrupted_request_keeps_identity_and_resume_skips_finished(self):
        first = FakeClient(interrupt=True)
        with self.assertRaises(StopRun):
            run(first, self.path, self.state, limit=0)
        persisted = json.loads(self.path.read_text())
        original_id = persisted['assessments']['a']['requestId']
        self.assertFalse(persisted['assessments']['a']['finished'])
        second = FakeClient()
        run(second, self.path, persisted, limit=0)
        starts = [args for name, args in second.calls if name == 'start_photo_assessment']
        self.assertEqual(starts[0]['requestId'], original_id)
        self.assertEqual([args['burstId'] for args in starts], ['a', 'b'])
        third = FakeClient()
        run(third, self.path, json.loads(self.path.read_text()), limit=0)
        self.assertFalse(any(name == 'start_photo_assessment' for name, _ in third.calls))

    def test_limit_counts_only_additional_bursts(self):
        self.state['assessments']['a'] = {'finished': True}
        self.state['bursts'].append({'id': 'c'})
        client = FakeClient()
        with self.assertRaises(StopRun):
            run(client, self.path, self.state, limit=1)
        starts = [args['burstId'] for name, args in client.calls if name == 'start_photo_assessment']
        self.assertEqual(starts, ['b'])
        self.assertTrue(json.loads(self.path.read_text())['assessments']['b']['finished'])

    def test_lost_submission_reply_has_checkpoint_for_identical_replay(self):
        class LostReply(FakeClient):
            def call(self, name, **arguments):
                if name == 'start_photo_assessment':
                    self.submitted = copy.deepcopy(arguments)
                    raise RuntimeError('Connection lost after admission')
                return super().call(name, **arguments)

        client = LostReply()
        with self.assertRaises(RuntimeError):
            run(client, self.path, self.state, limit=0)
        next_client = FakeClient()
        with self.assertRaises(StopRun):
            run(next_client, self.path, json.loads(self.path.read_text()), limit=1)
        replay = next(args for name, args in next_client.calls if name == 'start_photo_assessment')
        self.assertEqual(replay, client.submitted)


if __name__ == '__main__':
    unittest.main()
