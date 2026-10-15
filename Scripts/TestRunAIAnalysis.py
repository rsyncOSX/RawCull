"""Validate selection and runner failure reporting without installed models."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('RunAIAnalysis.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_selection_is_sorted_unbounded_and_nonrecursive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['g.ARW', 'c.arw', 'a.ARW', 'f.ARW', 'b.ARW', 'e.ARW', 'd.ARW', '0.jpg']:
                (root / name).touch()
            (root / '0.ARW').mkdir()
            self.assertEqual(runner.select_names(root), ['a.ARW', 'b.ARW', 'c.arw', 'd.ARW', 'e.ARW', 'f.ARW', 'g.ARW'])
            self.assertEqual(runner.select_names(root, 2), ['a.ARW', 'b.ARW'])

    def run_fixture(self, complete, code):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = root / 'raw'
            raw.mkdir()
            (raw / 'one.ARW').write_bytes(b'raw')
            for name in ['Qwen/qwen3_vl_2b', 'SAM3', 'CLIP-DataComp']:
                (root / 'models' / name).mkdir(parents=True)
            output = root / 'evidence'
            def run(command, **kwargs):
                environment = kwargs['env']
                self.assertEqual(environment['TEST_RUNNER_RAWCULL_ANALYSIS_RUN'], '1')
                self.assertEqual(json.loads(environment['TEST_RUNNER_RAWCULL_ANALYSIS_NAMES']), ['one.ARW'])
                self.assertIn('-only-testing:RawCullTests/AIAnalysisRealModelTests', command)
                if complete:
                    output.mkdir()
                    (output / 'diagnostic.json').write_text('[]')
                return type('Result', (), {'returncode': code})()
            with patch('sys.argv', ['runner', '--directory', str(raw), '--models', str(root / 'models'), '--output', str(output)]), \
                    patch.object(runner.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                return runner.main()

    def test_missing_evidence_cannot_pass(self):
        self.assertEqual(self.run_fixture(False, 0), 1)

    def test_failures_are_preserved(self):
        self.assertEqual(self.run_fixture(True, 65), 65)

    def test_complete_run_passes(self):
        self.assertEqual(self.run_fixture(True, 0), 0)


if __name__ == '__main__':
    unittest.main()
