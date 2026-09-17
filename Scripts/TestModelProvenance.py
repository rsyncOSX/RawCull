import json
from pathlib import Path
import shutil
import tempfile
import unittest
from VerifyModelProvenance import validate


class ModelProvenanceTests(unittest.TestCase):
    def test_invalid_enabled_evidence_is_rejected(self):
        source = Path(__file__).resolve().parent.parent
        self.assertEqual(validate(source), ['clipDataComp', 'qwen3VL2B', 'sam3'])
        for mutation in ['blocked', 'missing', 'malformed', 'hash', 'size', 'enable_sam', 'enable_sam_download', 'unknown_flag', 'invalid_status', 'missing_field', 'wrong_filter', 'model_path', 'revision', 'wrong_pack_id', 'invalid_pack_format', 'wrong_app_id', 'wrong_hosting', 'invalid_record_uuid', 'invalid_version_uuid', 'invalid_version', 'invalid_processing_date', 'invalid_beta_uuid', 'invalid_beta_state']:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copy(source / "RawCull-AppStore-Info.plist", root / "RawCull-AppStore-Info.plist")
                catalog = Path('RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift')
                (root / catalog).parent.mkdir(parents=True)
                # Start rejection fixtures from the release-ready DataComp-only configuration.
                (root / catalog).write_text((source / catalog).read_text().replace(
                    'includeSAM3Download = true', 'includeSAM3Download = false').replace(
                    'includeSAM3 = true', 'includeSAM3 = false').replace(
                    'includeQwen3VL2BDownload = true', 'includeQwen3VL2BDownload = false'))
                shutil.copytree(source / 'ModelAssets/Notices', root / 'ModelAssets/Notices')
                self.assertEqual(validate(root), ['clipDataComp'])
                path = root / 'ModelAssets/Notices/CLIP-DataComp/PROVENANCE.json'
                record = json.loads(path.read_text())
                if mutation == 'missing':
                    path.unlink()
                elif mutation == 'malformed':
                    path.write_text('{')
                elif mutation.startswith('enable_sam'):
                    sam_path = root / 'ModelAssets/Notices/SAM3/PROVENANCE.json'
                    sam_record = json.loads(sam_path.read_text())
                    sam_record['release_status'] = 'blocked'
                    sam_record['release_blocker'] = 'Test unresolved release evidence'
                    sam_path.write_text(json.dumps(sam_record))
                    flag = 'includeSAM3Download' if mutation.endswith('download') else 'includeSAM3'
                    text = (root / catalog).read_text().replace(flag + ' = false', flag + ' = true')
                    (root / catalog).write_text(text)
                elif mutation == 'wrong_filter':
                    (root / catalog).write_text((root / catalog).read_text().replace('RawCullAIModelInclusion.downloadIDs.contains($0.id)', 'true'))
                elif mutation == 'unknown_flag':
                    (root / catalog).write_text((root / catalog).read_text().replace('includeSAM3 = false', 'includeSAM3 = computedValue'))
                else:
                    if mutation == 'wrong_pack_id':
                        record['release']['asset_pack_id'] = 'no.blogspot.RawCull.models.wrong'
                    elif mutation == 'invalid_pack_format':
                        invalid_id = 'rawcull.clip-datacomp'
                        record['release']['asset_pack_id'] = invalid_id
                        (root / catalog).write_text((root / catalog).read_text().replace('rawcull-clip-datacomp', invalid_id))
                    elif mutation == 'wrong_app_id':
                        record['release']['app_bundle_id'] = 'no.blogspot.Wrong'
                    elif mutation == 'wrong_hosting':
                        record['release']['hosting'] = 'self-hosted'
                    elif mutation == 'invalid_record_uuid':
                        record['release']['asset_pack_record_id'] = 'not-a-uuid'
                    elif mutation == 'invalid_version_uuid':
                        record['release']['asset_pack_version_id'] = 'not-a-uuid'
                    elif mutation == 'invalid_version':
                        record['release']['asset_pack_version'] = 'latest'
                    elif mutation == 'invalid_processing_date':
                        record['release']['processing_date'] = 'September 17, 2026'
                    elif mutation == 'invalid_beta_uuid':
                        record['release']['internal_beta_release_id'] = 'not-a-uuid'
                    elif mutation == 'invalid_beta_state':
                        record['release']['internal_beta_state'] = 'processing'
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
