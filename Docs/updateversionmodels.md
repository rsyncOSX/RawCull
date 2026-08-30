# Updating the AI model release version

This checklist describes how to publish a new version of RawCull's Managed
Background Assets model release and update RawCull to use it. The downloadable
files are extensionless Managed Background Assets asset packs, not Android
`.aar` files.

The examples below use `v3`. Replace `v3` and manifest asset-pack version `3`
with the release being prepared.

## Models and stable identifiers

| Model | Asset-pack ID | Manifest destination | App resource name |
|---|---|---|---|
| DataComp CLIP | `no.blogspot.RawCull.models.clip-datacomp` | `Models/CLIP-DataComp` | `CLIP-DataComp` |
| OpenAI CLIP | `no.blogspot.RawCull.models.clip-openai` | `Models/CLIP-OpenAI` | `CLIP-OpenAI` |
| Meta SAM 3 | `no.blogspot.RawCull.models.sam3` | `Models/SAM3` | `SAM3` |

Do not change an asset-pack ID or destination merely to publish a new
version. Change them only when intentionally creating a different pack or
moving its installed contents. The IDs in the generated manifest must exactly
match `RawCullAIModelDownloadCatalog.production`.

## 1. Prepare and verify every model pack

For each model included in the new release:

1. Build the final model bundle and its tokenizer or other required resources.
2. Include the complete applicable licence and third-party notice files.
3. Record the immutable upstream revision and source-file checksums where
   available.
4. Record the converted-model fingerprint and conversion tool revisions.
5. Confirm that the directory selected by `ModelAssets/manifest.template.json`
   contains only files intended for redistribution.
6. Generate the deployable asset pack with the release version of Xcode's
   Managed Background Assets tools.
7. Calculate the SHA-256 and byte size from the exact generated archive that
   will be uploaded. Do not calculate them from its source directory.

Use the following per-model evidence:

### DataComp CLIP

- Upstream project and model page.
- Immutable reference or source revision.
- Source checkpoint checksum when available.
- Tokenizer revision and checksum.
- Converted model fingerprint.
- Asset-pack archive SHA-256 and byte size.
- OpenCLIP/DataComp, OpenAI tokenizer, and Apple conversion-recipe notices.

### OpenAI CLIP

- Immutable `openai/clip-vit-base-patch32` revision.
- `pytorch_model.bin` SHA-256 and byte size.
- Tokenizer revision and checksum.
- Converted model fingerprint.
- Asset-pack archive SHA-256 and byte size.
- OpenAI CLIP and Apple conversion-recipe notices.

### Meta SAM 3

- Immutable Meta SAM 3 revision.
- Source checkpoint checksum and gated-download evidence.
- Converted model fingerprint.
- Asset-pack archive SHA-256 and byte size.
- Complete SAM License and Apple conversion-recipe notice.
- A documented decision confirming that redistribution through an ungated
  Managed Background Assets URL is compatible with the SAM License, gated
  access conditions, and other applicable terms.

SAM 3 must remain `releaseReadiness: .blocked` and must not appear in the
deployable manifest until its redistribution review is complete. Publishing a
SAM 3 archive is not, by itself, evidence that this review was completed.

## 2. Generate the new release manifest

Use `ModelAssets/manifest.template.json` as the developer-side source. Update
that template only if a model is added or removed, or an asset-pack ID, source
directory, destination, platform, or download policy changes.

The generated `manifest.json` for `v3` must contain, for every released pack:

- the stable asset-pack ID;
- manifest asset-pack `version` value `3`;
- the final archive byte size;
- an on-demand download policy;
- third-party hosting configuration; and
- a URL under
  `https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/`.

Example asset URLs:

```text
https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/no.blogspot.RawCull.models.clip-datacomp
https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/no.blogspot.RawCull.models.clip-openai
https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/no.blogspot.RawCull.models.sam3
```

Include the SAM 3 entry only after its app descriptor and provenance are
release-ready.

## 3. Update files in the RawCull repository

### Manifest URL

Update both copies of the production manifest URL:

1. `RawCull-Info.plist`
   - Change `BAManifestURL` from the old release to
     `https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/manifest.json`.
2. `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift`
   - Change `RawCullAIModelDownloadSource.productionManifestURL` to the same
     v3 URL.

These values must remain identical.

### Production model catalog

Update `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift` for
each released model:

- `modelVersion` when the model or export version changed;
- `upstreamRevision` when the source revision changed;
- `expectedArchiveSHA256` using the final uploaded archive;
- `downloadByteCount` using the final uploaded archive;
- `installedByteCount` when a reliable installed size is recorded;
- model, source, conversion, and licence URLs when they changed;
- bundled licence resource name and checksum when licence text changed; and
- `releaseReadiness`.

Set `releaseReadiness: .ready` only after the archive, licence, and provenance
checks are complete. A pack that remains `.blocked` is deliberately skipped
before RawCull asks Background Assets for its manifest state.

Also update `RawCullAIModelInclusion` when a model should become visible or be
removed from Settings. For SAM 3, this includes `includeSAM3` as well as its
release-readiness state.

### Provenance and notices

Update the following directory for each model included in the release:

```text
ModelAssets/Notices/CLIP-DataComp/
ModelAssets/Notices/CLIP-OpenAI/
ModelAssets/Notices/SAM3/
```

In each `PROVENANCE.json`, update:

- `catalog_version` when advancing the release record version;
- `release_status`;
- `release.tag`;
- `release.asset_url`;
- upstream revisions and source checksums;
- tokenizer evidence where applicable;
- converted-model fingerprints; and
- conversion tool and dependency revisions.

Archive byte sizes and SHA-256 values belong in the generated external
manifest, the application download catalog, and release-host metadata. Do not
embed them in a provenance file packaged inside the same archive: changing the
embedded record would change the archive checksum and make the record
self-referential.

Remove `release_blocker` only when the blocker has genuinely been resolved.
Keep it present and nonempty for blocked models.

Update each `NOTICE.md` when its release-status section names the previous
release, when the model evidence changed, or when attribution changed. Replace
licence `.txt` files only when the applicable complete licence text changed;
then update every checksum that refers to the replaced file, including bundled
licence resources under `RawCull/Resources/ModelLicences`.

### Documentation

Update `ModelAssets/README.md` with:

- the new release tag;
- archive SHA-256 and byte-size evidence;
- model revisions and source checksums;
- distribution state for all three models;
- the new production manifest URL; and
- which packs the generated manifest publishes.

Update other model validation or release-decision documents only when their
recorded model revision, fingerprint, quality result, or release status is no
longer current.

## 4. Update tests

Update `RawCullTests/RawCullAIModelDownloadsTests.swift`:

- expected production catalog model IDs;
- release-readiness assertions;
- upstream revisions;
- expected archive SHA-256 values;
- download byte counts; and
- the regression asserting that every published model reaches the Background
  Assets runtime state.

Update `RawCullTests/ReleaseMetadataTests.swift`:

- expected `BAManifestURL`;
- expected count of descriptors with `expectedArchiveSHA256: nil`;
- expected count of blocked descriptors;
- expected manifest URL in `ModelAssets/README.md`; and
- expected ready or blocked status for each provenance file.

If `ModelAssets/manifest.template.json` changes, also update its expected pack
IDs and destinations in `ReleaseMetadataTests`.

## 5. Publish in the correct order

1. Create the GitHub release or prerelease tag `v3`.
2. Upload every final asset-pack archive first.
3. Verify each uploaded archive's byte size and SHA-256 against the catalog and
   provenance record.
4. Upload the generated `manifest.json` last. This prevents clients from seeing
   a manifest that points to missing or incomplete archives.
5. Download the production manifest and confirm every ID, version, size, and
   URL.
6. Verify that every production URL returns the intended immutable file.
7. Only then ship a RawCull build whose `BAManifestURL` points to v3.

Do not replace an asset in place after publishing the manifest. If any archive
changes, generate a new archive checksum and byte size and publish a new model
release version.

## 6. Verification

Before shipping RawCull, run formatting and the focused release tests:

```sh
swiftformat --config .swiftformat \
  RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift \
  RawCullTests/RawCullAIModelDownloadsTests.swift \
  RawCullTests/ReleaseMetadataTests.swift

xcodebuild test \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  -only-testing:RawCullTests/RawCullAIModelDownloadsTests \
  -only-testing:RawCullTests/ReleaseMetadataTests
```

Then test the model-download sheet on a supported macOS build:

For the distinction between Apple's macOS build number, RawCull's marketing/build
versions, development versus distribution signing, and the required beta/RC test
procedure, see [macOS Background Assets and RawCull release builds](macos-background-assets-release.md).

- every released model is shown as ready or installed;
- every blocked model is shown as distribution blocked and cannot download;
- downloads resolve the expected asset-pack ID and destination;
- downloaded model validation succeeds;
- removing and redownloading each pack succeeds; and
- switching between DataComp CLIP and OpenAI CLIP uses separate model indexes.

## Release checklist

- [ ] DataComp CLIP archive, licence, provenance, revision, hash, and size verified.
- [ ] OpenAI CLIP archive, licence, provenance, revision, hash, and size verified.
- [ ] SAM 3 redistribution review completed, or SAM 3 remains blocked and absent from the manifest.
- [ ] Generated manifest uses the new version and final archive URLs and sizes.
- [ ] Asset packs uploaded before `manifest.json`.
- [ ] Both RawCull manifest URL declarations point to the new release.
- [ ] Production model catalog matches the uploaded archives.
- [ ] Per-model provenance and notices match the new release.
- [ ] `ModelAssets/README.md` matches the new release.
- [ ] Download and release-metadata tests pass.
- [ ] Production URLs and an actual download have been verified.
