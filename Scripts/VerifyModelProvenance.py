#!/usr/bin/env python3
"""Fail-closed release check of the Swift production catalog and recorded evidence."""
import hashlib
import json
from pathlib import Path
import re
import plistlib
import sys
import uuid


def require(condition, message):
    if not condition:
        raise ValueError(message)


def require_uuid(value, message):
    require(isinstance(value, str), message)
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        raise ValueError(message)
    require(str(parsed) == value, message)


def validate(root):
    with (root / 'RawCull-AppStore-Info.plist').open('rb') as handle:
        app_store_info = plistlib.load(handle)
    require(app_store_info.get('BAUsesAppleHosting') is True, 'App Store build must use Apple hosting')
    require(app_store_info.get('BAHasManagedAssetPacks') is True, 'App Store build must declare managed asset packs')
    require(app_store_info.get('BAAppGroupID') == 'group.no.blogspot.RawCull.model-assets', 'App Store app group mismatch')
    forbidden_keys = {
        'BAManifestURL',
        'BAInitialDownloadRestrictions',
        'BAEssentialMaxInstallSize',
        'BAMaxInstallSize',
    }
    require(not forbidden_keys.intersection(app_store_info), 'App Store plist contains self-hosted Background Assets keys')
    source = (root / 'RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift').read_text()
    inclusion = source.split('nonisolated enum RawCullAIModelInclusion {', 1)[1].split('nonisolated struct', 1)[0]
    flags = dict(re.findall(r'static let (include\w+) = (true|false)\b', inclusion))
    declared = re.findall(r'static let (include\w+)\s*=', inclusion)
    require(set(flags) == set(declared) and len(flags) == len(declared), 'Unrecognized inclusion flag expression')
    # Derive enabled downloads and selectable models from the actual inclusion code.
    downloads = re.findall(r'if (include\w+)\s*\{\s*ids.insert\(\.(\w+)\)', inclusion)
    selections = re.findall(r'case \.(\w+): (include\w+)', inclusion)
    ids = dict(re.findall(r'case (\w+) = "([^"]+)"', source.split('/// Code-only')[0]))
    ids.update({name: name for name in re.findall(r'^    case (\w+)$', source.split('/// Code-only')[0], re.M)})
    blocks = source.split('static let prepared = Self(', 1)[1].split('static let production', 1)[0]
    descriptors = {}
    for block in blocks.split('RawCullAIModelDownloadDescriptor(')[1:]:
        key = re.search(r'id: \.(\w+),', block).group(1)
        require(key not in descriptors, f'Duplicate descriptor {key}')
        descriptors[key] = block
    require(set(descriptors).issubset(ids), 'Descriptor uses an unknown model ID')
    require(set(flags) == {flag for flag, _ in downloads} | {flag for _, flag in selections}, 'Unmapped inclusion flag')
    enabled = {key for flag, key in downloads if flags[flag] == 'true'}
    for name, flag in selections:
        if flags[flag] == 'true':
            matches = [key for key in ids if key.lower() == name.lower() or key.lower() == ('clip' + name).lower()]
            require(len(matches) == 1, f'Unknown selectable model {name}')
            enabled.add(matches[0])
    require(enabled.issubset(descriptors), 'Every enabled model ID must have one descriptor')
    production = source.split('static let production', 1)[1].split('private static func', 1)[0]
    require(re.sub(r'\s+', '', production) == '=Self(models:prepared.models.filter{RawCullAIModelInclusion.downloadIDs.contains($0.id)},)', 'Unrecognized production catalog filter')
    for key in enabled:
        block = descriptors[key]
        def field(name):
            match = re.search(r'\b' + name + r': "([^"]+)"', block)
            require(match is not None, f'{key}: missing {name}')
            return match.group(1)
        resource = field('resourceName')
        directory = root / 'ModelAssets/Notices' / resource
        record = json.loads((directory / 'PROVENANCE.json').read_text())
        require(record['release_status'] == 'ready' and not record.get('release_blocker'), f'{key}: provenance is blocked')
        require('releaseReadiness: .ready,' in block, f'{key}: descriptor is blocked')
        require(record['model']['bundle'] == resource, f'{key}: bundle mismatch')
        model_path = field('assetPackModelPath')
        require(record['model']['asset'] == model_path or record['model']['asset'].startswith(model_path + '/'), f'{key}: model path mismatch')
        upstream = record['upstream']
        revision = upstream.get('reference_revision') or upstream.get('local_cache_snapshot_revision')
        require(revision == field('upstreamRevision'), f'{key}: upstream revision mismatch')
        archive = record['release']
        sha = field('expectedArchiveSHA256')
        require(re.fullmatch('[0-9a-f]{64}', sha), f'{key}: invalid archive hash')
        size = re.search(r'downloadByteCount: ([0-9_]+),', block)
        require(size is not None, f'{key}: missing archive size')
        require(archive['archive_sha256'] == sha, f'{key}: archive hash mismatch')
        require(type(archive['archive_byte_count']) is int and archive['archive_byte_count'] == int(size.group(1).replace('_', '')) > 0, f'{key}: archive size mismatch')
        require(archive['hosting'] == 'apple', f'{key}: release is not Apple-hosted')
        require(archive['app_bundle_id'] == 'no.blogspot.RawCull', f'{key}: app bundle ID mismatch')
        require(archive['asset_pack_id'] == field('assetPackID'), f'{key}: asset-pack ID mismatch')
        require(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?', archive['asset_pack_id']) is not None, f'{key}: invalid Apple asset-pack ID')
        require(archive['processing_status'] in {'pending-upload', 'processing', 'succeeded'}, f'{key}: invalid processing status')
        require(archive['review_state'] in {'not-submitted', 'in-review', 'approved'}, f'{key}: invalid review state')
        if archive['processing_status'] == 'succeeded':
            require_uuid(archive.get('asset_pack_record_id'), f'{key}: invalid App Store Connect asset-pack record ID')
            require_uuid(archive.get('asset_pack_version_id'), f'{key}: invalid App Store Connect asset-pack version ID')
            version = archive.get('asset_pack_version')
            require(isinstance(version, str) and re.fullmatch(r'[1-9][0-9]*', version) is not None, f'{key}: invalid Apple asset-pack version')
            require(re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', archive.get('processing_date', '')) is not None, f'{key}: invalid processing date')
            require_uuid(archive.get('internal_beta_release_id'), f'{key}: invalid internal beta release ID')
            require(archive.get('internal_beta_state') == 'ready-for-testing', f'{key}: invalid internal beta state')
        require(record['licences'], f'{key}: missing notices')
        for notice in record['licences']:
            require(hashlib.sha256((directory / notice['file']).read_bytes()).hexdigest() == notice['sha256'], f'{key}: notice hash mismatch')
    return sorted(enabled)


if __name__ == '__main__':
    try:
        print('Model provenance verified: ' + ', '.join(validate(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)))
    except (ValueError, KeyError, OSError, IndexError, AttributeError, TypeError) as error:
        sys.exit(f'Release blocked: invalid model provenance: {error}')
