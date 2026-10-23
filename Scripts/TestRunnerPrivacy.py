"""Runner privacy and process-state checks without invoking Xcode."""
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import RunAIAnalysis
import RunCombinedReviewSix


class RunnerPrivacyTests(unittest.TestCase):
    def test_private_outputs_restore_callers_umask_on_success_and_failure(self):
        for runner in (RunAIAnalysis, RunCombinedReviewSix):
            for fail in (False, True):
                with self.subTest(runner=runner.__name__, fail=fail), tempfile.TemporaryDirectory() as directory:
                    output = Path(directory) / 'evidence.json'

                    def run():
                        output.write_text('{}')
                        if fail:
                            raise ValueError('preflight failed')
                        return 0

                    previous = os.umask(0o022)
                    try:
                        with patch.object(runner, '_main', side_effect=run):
                            if fail:
                                with self.assertRaisesRegex(ValueError, 'preflight failed'):
                                    runner.main()
                            else:
                                self.assertEqual(runner.main(), 0)
                        current = os.umask(0o022)
                        self.assertEqual(current, 0o022)
                        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
                    finally:
                        os.umask(previous)


if __name__ == '__main__':
    unittest.main()
