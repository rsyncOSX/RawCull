import base64
import json
import tempfile
import unittest
from pathlib import Path
from FreezeCombinedReviewBaseline import freeze


class BaselineInventoryTests(unittest.TestCase):
    def test_inventory_keeps_identity_payload_and_hash_without_mutating_export(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / 'baseline.json'
            run.write_text(json.dumps({'kind': 'run', 'value': {'snapshot': {'id': 'baseline', 'models': {'sam': 'pinned'}}, 'work': [{'id': 'work'}]}}))
            stage = root / 'stage.json'
            payload = {'subjects': [{'id': 'subject', 'maskInputReference': 'mask'}]}
            stage.write_text(json.dumps({'kind': 'stage', 'value': {'payload': base64.b64encode(json.dumps(payload).encode()).decode()}}))
            original = {p.name: p.read_bytes() for p in root.iterdir()}
            result = freeze(root, 'baseline')
            self.assertEqual(result['files'][0]['snapshot']['models'], {'sam': 'pinned'})
            self.assertEqual(result['files'][1]['payload'], payload)
            self.assertEqual(len(result['files'][0]['sha256']), 64)
            self.assertEqual(original, {p.name: p.read_bytes() for p in root.iterdir()})

    def test_missing_export_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            result = freeze(Path(directory) / 'missing', 'baseline')
            self.assertFalse(result['exportAvailable'])
            self.assertEqual(result['files'], [])


if __name__ == '__main__':
    unittest.main()
