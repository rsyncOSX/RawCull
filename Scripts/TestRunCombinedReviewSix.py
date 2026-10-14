#!/usr/bin/env python3
"""Runner orchestration checks; no Xcode, models or private photographs required."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('RunCombinedReviewSix.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_progress_tracks_execution_order_and_terminal_reports(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            runs = output / 'runs'
            runs.mkdir()
            manifest = runs / 'run.json'
            run = {'snapshot': {'files': [
                {'id': 'b', 'displayName': 'second.ARW'},
                {'id': 'a', 'displayName': 'first.ARW'}]}, 'work': []}
            def save():
                manifest.write_text(json.dumps({'value': run}))
            save()
            self.assertEqual(runner.progress_message(output), 'Running 1 out of 2: first.ARW')
            run['work'].append({'imageID': 'a', 'stage': 'report', 'state': 'running'})
            save()
            self.assertEqual(runner.progress_message(output), 'Running 1 out of 2: first.ARW')
            run['work'][0]['state'] = 'failed'
            save()
            self.assertEqual(runner.progress_message(output), 'Running 2 out of 2: second.ARW')
            run['work'].append({'imageID': 'b', 'stage': 'report', 'state': 'completed'})
            save()
            self.assertIn('2 out of 2; running comparison', runner.progress_message(output))
            for file in run['snapshot']['files']:
                file['id'] = {'rawValue': file['id']}
            for work in run['work']:
                work['imageID'] = {'rawValue': work['imageID']}
            save()
            self.assertIn('2 out of 2; running comparison', runner.progress_message(output))
            manifest.write_text('{')
            self.assertIsNone(runner.progress_message(output))

    def run_fixture(self, callback, exit_code):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw = root / 'raw'
            raw.mkdir()
            for name in runner.NAMES:
                (raw / name).write_bytes(name.encode())
            for name in ['Qwen/qwen3_vl_2b', 'SAM3', 'CLIP-DataComp']:
                (root / 'models' / name).mkdir(parents=True)
            output = root / 'evidence'
            def run(command, **kwargs):
                self.assertEqual(kwargs['env']['TEST_RUNNER_RAWCULL_COMBINED_SIX_RUN'], '1')
                self.assertEqual(json.loads(kwargs['env']['TEST_RUNNER_RAWCULL_COMBINED_SIX_NAMES']), sorted(runner.NAMES))
                self.assertEqual(kwargs['env']['TEST_RUNNER_RAWCULL_COMBINED_SIX_FROZEN'], '0')
                callback(output)
                return type('Result', (), {'returncode': exit_code})()
            arguments = ['runner', '--directory', str(raw), '--models', str(root / 'models'), '--output', str(output)]
            with patch('sys.argv', arguments), \
                    patch.object(runner.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                return runner.main()

    def test_first_six_are_sorted_and_ignore_non_raw_and_subdirectories(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ['g.ARW', 'c.arw', 'a.ARW', 'f.ARW', 'b.ARW', 'e.ARW', 'd.ARW', '0.jpg']:
                (root / name).touch()
            (root / '0.ARW').mkdir()
            self.assertEqual(runner.select_names(root), ['a.ARW', 'b.ARW', 'c.arw', 'd.ARW', 'e.ARW', 'f.ARW'])
            self.assertEqual(runner.select_names(root, frozen=True), runner.NAMES)

    def test_fewer_than_six_fails_before_xcode(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch('sys.argv', ['runner', '--directory', temporary]), patch.object(runner.subprocess, 'run') as run, \
                    contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    runner.main()
                self.assertEqual(error.exception.code, 2)
                run.assert_not_called()

    def test_zero_exit_without_executed_test_fails(self):
        self.assertEqual(self.run_fixture(lambda output: None, 0), 1)

    def test_failing_test_keeps_diagnostic_and_failure(self):
        def save(output):
            output.mkdir()
            (output / 'diagnostic.json').write_text('{}')
        self.assertEqual(self.run_fixture(save, 65), 65)

    def test_success_requires_diagnostic(self):
        def save(output):
            output.mkdir()
            (output / 'diagnostic.json').write_text('{}')
        self.assertEqual(self.run_fixture(save, 0), 0)


if __name__ == '__main__':
    unittest.main()
