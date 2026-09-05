import json
from pathlib import Path
import shutil
import tempfile
import unittest
from VerifyModelProvenance import validate


class ModelProvenanceTests(unittest.TestCase):
    def test_invalid_enabled_evidence_is_rejected(self):
        source = Path(__file__).resolve().parent.parent
        for mutation in ['blocked', 'missing', 'malformed', 'hash', 'size', 'enable_sam', 'enable_sam_download', 'unknown_flag', 'invalid_status', 'missing_field', 'wrong_filter', 'model_path', 'revision', 'stale_release_url', 'stale_release_tag']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copy(source / "RawCull-Info.plist", root / "RawCull-Info.plist")
                catalog = Path('RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift')
                (root / catalog).parent.mkdir(parents=True)
                shutil.copy(source / catalog, root / catalog)
                shutil.copytree(source / 'ModelAssets/Notices', root / 'ModelAssets/Notices')
                self.assertEqual(validate(root), ['clipDataComp'])
                path = root / 'ModelAssets/Notices/CLIP-DataComp/PROVENANCE.json'
                record = json.loads(path.read_text())
                if mutation == 'missing':
                    path.unlink()
                elif mutation == 'malformed':
                    path.write_text('{')
                elif mutation.startswith('enable_sam'):
                    flag = 'includeSAM3Download' if mutation.endswith('download') else 'includeSAM3'
                    text = (root / catalog).read_text().replace(flag + ' = false', flag + ' = true')
                    (root / catalog).write_text(text)
                elif mutation == 'wrong_filter':
                    (root / catalog).write_text((root / catalog).read_text().replace('RawCullAIModelInclusion.downloadIDs.contains($0.id)', 'true'))
                elif mutation == 'unknown_flag':
                    (root / catalog).write_text((root / catalog).read_text().replace('includeSAM3 = false', 'includeSAM3 = computedValue'))
                else:
                    if mutation == 'stale_release_url':
                        record['release']['asset_url'] = record['release']['asset_url'].replace('/v3/', '/v2/')
                    elif mutation == 'stale_release_tag':
                        record['release']['tag'] = 'v2'
                    elif mutation == 'model_path':
                        record['model']['asset'] = 'Models/Wrong/model.aimodel'
                    elif mutation == 'revision':
                        record['upstream']['reference_revision'] = 'wrong-revision'
                    elif mutation == 'missing_field':
                        del record['release']['archive_sha256']
                    elif mutation == 'invalid_status':
                        record['release_status'] = None
                    elif mutation == 'blocked':
                        record['release_status'] = 'blocked'
                    elif mutation == 'hash':
                        record['release']['archive_sha256'] = '0' * 64
                    else:
                        record['release']['archive_byte_count'] = 0
                    path.write_text(json.dumps(record))
                with self.assertRaises((ValueError, OSError, KeyError)):
                    validate(root)


if __name__ == '__main__':
    unittest.main()
