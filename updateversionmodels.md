# Integrating the v4 AI model release into RawCull

This checklist describes how to publish a new version of RawCull's Managed
Background Assets model release and update RawCull to use it. The downloadable
files are extensionless Managed Background Assets asset packs, not Android
`.aar` files.

Reviewed against the repository on September 8, 2026. Production currently points
to `v3`; this document describes the future `v4` migration. Updating this guide
does not switch the app to v4 or publish any assets. No v4 archive was supplied or
verified during this review, so its final hashes and sizes must be measured.

`v4` is the GitHub model-release tag; `4` is the intended per-pack manifest
version for this migration. Neither is the model architecture/version string,
`catalog_version` in provenance, RawCull's `MARKETING_VERSION`, its build number,
or the macOS version. Do not globally replace every occurrence of “3”.

## Models and stable identifiers

| Model | Asset-pack ID | Manifest destination | App resource name |
|---|---|---|---|
| DataComp CLIP | `no.blogspot.RawCull.models.clip-datacomp` | `Models/CLIP-DataComp` | `CLIP-DataComp` |
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

### Meta SAM 3

- Immutable Meta SAM 3 revision.
- Source checkpoint checksum and gated-download evidence.
- Converted model fingerprint.
- Asset-pack archive SHA-256 and byte size.
- Complete SAM License and Apple conversion-recipe notice.
- A documented decision confirming that redistribution through an ungated
  Managed Background Assets URL is compatible with the SAM License, gated
  access conditions, and other applicable terms.

SAM 3 is enabled in the current v3 release at the project owner’s direction, with verified archive
metadata recorded in its provenance. For future releases, keep any unresolved
release blocker until the corresponding release decision and evidence are recorded.

## 2. Generate the new release manifest

Use `ModelAssets/manifest.template.json` as the developer-side source. Update
that template only if a model is added or removed, or an asset-pack ID, source
directory, destination, platform, or download policy changes.

The generated `manifest.json` for `v4` must contain, for every released pack:

- the stable asset-pack ID;
- manifest asset-pack `version` value `4`;
- the final archive byte size;
- an on-demand download policy;
- third-party hosting configuration; and
- a URL under
  `https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v4/`.

Example asset URLs:

```text
https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v4/no.blogspot.RawCull.models.clip-datacomp
https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v4/no.blogspot.RawCull.models.sam3
```

Include SAM 3 in the deployable manifest only after its app descriptor and
provenance catalog are release-ready.

## 3. Update files in the RawCull repository

### Manifest URL

Update both copies of the production manifest URL:

1. `RawCull-Info.plist`
   - Change `BAManifestURL` from the old release to
     `https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v4/manifest.json`.
2. `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift`
   - Change `RawCullAIModelDownloadSource.productionManifestURL` to the same
     v4 URL.

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
removed from Settings. SAM 3 uses `includeSAM3Download` for the download sheet and `includeSAM3` for
selection and loading; both are currently enabled.

### Provenance and notices

Update the following directory for each model included in the release:

```text
ModelAssets/Notices/CLIP-DataComp/
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

The repository's `PROVENANCE.json` **must** include `release.archive_sha256`
and `release.archive_byte_count`, matching the application catalog. Both
`Scripts/VerifyModelProvenance.py` and `ReleaseMetadataTests` require them for
enabled models. Record the final v4 tag and archive URL there too.

If provenance is also included inside the pack, create a separate staging copy
without that archive's final checksum and byte count. Freeze the staging tree,
package it, then write final archive evidence only to the repository copy and
external release records. Do not copy that updated record back into the frozen
pack and rebuild without recalculating all archive evidence. This avoids a
self-referential checksum while satisfying the repository validator.

Let Apple's tool generate its supported download-manifest fields; do not invent
an `archive_sha256` field in the framework manifest. The repository provenance
schema and Apple's download-manifest schema are different.

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
- distribution state for both models;
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
- readiness assertions for prepared and production descriptors;
- expected manifest URL in `ModelAssets/README.md`; and
- expected ready or blocked status for each provenance file.

If `ModelAssets/manifest.template.json` changes, also update its expected pack
IDs and destinations in `ReleaseMetadataTests`.

## 5. Publish in the correct order

1. Create the GitHub release or prerelease tag `v4`.
2. Upload every final asset-pack archive first.
3. Verify each uploaded archive's byte size and SHA-256 against the catalog and
   provenance record.
4. Upload the generated `manifest.json` last. This prevents clients from seeing
   a manifest that points to missing or incomplete archives.
5. Download the production manifest and confirm every ID, version, size, and
   URL.
6. Verify that every production URL returns the intended immutable file.
7. Only then ship a RawCull build whose `BAManifestURL` points to v4.

Do not replace an asset in place after publishing the manifest. If any archive
changes, generate a new archive checksum and byte size and publish a new model
release version.

## 6. Verification

Before shipping RawCull, run the provenance checks from the project root:

```sh
python3 Scripts/VerifyModelProvenance.py
python3 Scripts/TestModelProvenance.py
```

The validator derives enabled models from inclusion flags and checks readiness,
model paths, upstream revision, archive hash/size, release URL/tag, and notice
hashes. It does not download archives or validate inference quality. Its parser
expects specific Swift declaration patterns; adding a new model or changing
those patterns may require updating the validator and its mutation tests.

Then run formatting for changed Swift files and the focused release tests:

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

The previously referenced `macos-background-assets-release.md` is absent from
this checkout. Use the actual runtime guard in
`RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift` and the
current app/extension build settings when selecting a supported test machine.
Test both the development build and the intended signed distribution build.

- every released model is shown as ready or installed;
- every blocked model is shown as distribution blocked and cannot download;
- downloads resolve the expected asset-pack ID and destination;
- downloaded model validation succeeds;
- removing and redownloading each pack succeeds;

## Release checklist

- [ ] DataComp CLIP archive, licence, provenance, revision, hash, and size verified.
- [ ] SAM 3 redistribution review completed, or SAM 3 remains blocked and absent from the manifest.
- [ ] Generated manifest uses the new version and final archive URLs and sizes.
- [ ] Asset packs uploaded before `manifest.json`.
- [ ] Both RawCull manifest URL declarations point to the new release.
- [ ] Production model catalog matches the uploaded archives.
- [ ] Per-model provenance and notices match the new release.
- [ ] `ModelAssets/README.md` matches the new release.
- [ ] Download and release-metadata tests pass.
- [ ] Production URLs and an actual download have been verified.

## 7. Code map and runtime behavior

Paths below are relative to the project root; symbols are more durable references
than line numbers as the implementation changes.

| File | What to inspect or update for v4 |
|---|---|
| `RawCull-Info.plist` | `BAManifestURL`; keep `BAUsesAppleHosting = NO`, app-group ID, on-demand allowances, and GitHub domain allowlist consistent with self-hosting. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift` | `RawCullAIModelDownloadSource.productionManifestURL`, runtime availability guard, `state(for:)`, `download`, and `modelURL(for:)`. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift` | Stable IDs, `RawCullAIModelInclusion`, `prepared` descriptors, filtered `production`, licence hashes, and release readiness. |
| `RawCull/Intelligence/Contracts/RawCullAIModels.swift` | `RawCullCLIPModel`, `RawCullSegmentationModel`, resource names, defaults, and `RawCullAIPaths`. |
| `RawCull/Intelligence/Composition/RawCullAIIntegration.swift` | Provider factories, resource managers, `setManagedModelLocations`, selected providers, and model identity. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelResourceManager.swift` | Managed URL precedence, capability validation, provider construction, and validation cache. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelManagementModel.swift` | Download/readiness flow and licence gating. |
| `RawCull/Intelligence/ModelManagement/RawCullAIModelLicenceAcceptance.swift` | Acceptance matching and persistent acceptance records. |
| `RawCull/Views/Settings/AIModelDownloadsView.swift` | User-visible metadata, licence review, progress, and model actions. |
| `RawCullModelDownloader/RawCullModelDownloader.swift` | Self-hosted `ManagedDownloaderExtension`; a release tag change needs no extension implementation change. |
| `RawCull.xcodeproj/project.pbxproj` | PhotoAIKit products, package requirement, app/extension configuration. |
| `RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Exact PhotoAIKit dependency revision used to validate the export. |
| `Scripts/VerifyModelProvenance.py`, `Scripts/TestModelProvenance.py` | Fail-closed evidence validation and mutation coverage. |

`expectedArchiveSHA256` is release metadata: the current download service does
not hash the downloaded archive against this property. Background Assets owns
archive download/installation, and PhotoAIKit owns model-bundle capability and
cryptographic validation through the provider factory. A matching catalog value
alone does not prove that an installed model was checked against that archive
hash. Validate the actual hosted bytes separately.

`download` requests `requireLatestVersion: true`. However, `state(for:)` returns
an installed location immediately if the pack is already locally available;
“installed” alone does not demonstrate migration from v3 to v4. Test an upgrade
with an existing v3 installation as well as a clean download, and verify the
loaded model identity/fingerprint. If the UI cannot request the new version,
resolve that behavior before shipping; changing a URL is insufficient evidence.

Managed candidates precede local/bundled candidates. A local development model
can therefore hide a broken release path when the managed resource is absent.
Record the actual loaded path and provider identity during verification.

Acceptance records match model ID, model version, licence name/version, and
licence text hash. An export/modelVersion or licence change can require fresh
SAM 3 acceptance; the release tag alone is not the acceptance key.

## 8. Known v3 evidence — reference only

These values were read from the repository catalog and provenance, not rehashed
from hosted archives in this documentation review. They are **not v4 values**.

| Pack | v3 archive bytes | v3 archive SHA-256 |
|---|---:|---|
| DataComp CLIP | 282966632 | `cf433dcd199b44635a4ff0260bd8e79177e4907a4cfcb2f72043066b8cbe4ef7` |
| SAM 3 | 1542689157 | `dd0adc697060129435d4a70515011a37f547e1ad7cd530d943341bf3ca9184a9` |

The complete source revisions, tokenizer and licence hashes, conversion details,
and runtime `main.mlirb` hashes are in
`ModelAssets/Notices/CLIP-DataComp/PROVENANCE.json` and
`ModelAssets/Notices/SAM3/PROVENANCE.json`.
DataComp's source checkpoint hash and exporter-recorded source revision are
currently null. SAM 3's exporter fingerprint is null, and its provenance notes
that the cached upstream snapshot is not cryptographically bound to the export.
Preserve these limitations unless new evidence resolves them; do not substitute
an archive digest for missing source or exporter evidence.

For v4, retain a release evidence table with one row per pack containing:
asset-pack ID, model filename, model/export version, upstream revision, source
weight digest, tokenizer digest, runtime digest, exporter fingerprint and
algorithm, conversion/dependency revisions, final archive digest, archive byte
count, installed-size measurement, and immutable release URL. Mark unavailable
evidence explicitly rather than filling in guessed values.

## 9. Concrete packaging and checksum procedure

The following CLI syntax was checked against the installed Xcode-beta
`ba-package` help. Recheck `xcrun ba-package template` and subcommand help with
the Xcode selected for the release and record `xcodebuild -version` and
`xcrun ba-package --version` with the conversion evidence.

**The repository template is a developer inventory, not directly the current
`ba-package package` input.** It wraps multiple packs in `assetPacks` and uses
nested `directory.source/destination`. The inspected CLI accepts one pack per
input manifest and uses `directorySource` and `directoryDestination` selectors.
Generate a separate packaging manifest for each pack, for example:

```json
{
  "assetPackID": "no.blogspot.RawCull.models.clip-datacomp",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [
    {
      "directorySource": "CLIP-DataComp",
      "directoryDestination": "Models/CLIP-DataComp"
    }
  ],
  "platforms": ["macOS"]
}
```

Save this as `clip-datacomp.pack.json` in an external staging directory alongside
`CLIP-DataComp/`. Create `sam3.pack.json` with ID
`no.blogspot.RawCull.models.sam3`, source `SAM3`, and destination `Models/SAM3`.
Run the commands below from that staging directory. Include the entire
provider-compatible bundle, metadata, tokenizer, and notices, not only the
`.aimodel` directory. The current expected model paths are:

```text
Models/CLIP-DataComp/ViT-B-32-256-datacomp_s34b_b86k_float16_static.aimodel
Models/SAM3/sam3_float16.aimodel
```

```sh
mkdir -p release-v4
xcrun ba-package package clip-datacomp.pack.json \
  --output-path release-v4/no.blogspot.RawCull.models.clip-datacomp
xcrun ba-package package sam3.pack.json \
  --output-path release-v4/no.blogspot.RawCull.models.sam3

shasum -a 256 release-v4/no.blogspot.RawCull.models.clip-datacomp \
  release-v4/no.blogspot.RawCull.models.sam3
stat -f '%z %N' release-v4/no.blogspot.RawCull.models.clip-datacomp \
  release-v4/no.blogspot.RawCull.models.sam3

xcrun ba-package download-manifest create \
  release-v4/no.blogspot.RawCull.models.clip-datacomp \
  release-v4/no.blogspot.RawCull.models.sam3 \
  --asset-pack-versions 4 4 \
  --macos \
  --download-base-url https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v4/ \
  --output-path release-v4/manifest.json
```

Version arguments apply positionally to archive paths. Omitting them produces
version 0 with the inspected tool. Its `download-manifest update` command edits
an existing manifest in place and increments updated pack versions by one;
prefer explicit creation for this two-pack v4 release and inspect the result.
Publish a complete manifest covering all enabled production packs even if only
one model changed. Do not accidentally omit the other pack.

Use `shasum -a 256 /actual/path/to/file` separately for source weights, tokenizer,
licence text, and runtime `main.mlirb`. A directory-tree fingerprint must use the
exporter's recorded algorithm (`directory-tree-sha256-v1` in existing records),
not a hash of `ls` output, a zip, or concatenated file bytes. Archive size is the
exact file byte count, not `du` disk allocation or rounded megabytes.

After uploading archives, download into a fresh verification directory and
compare bytes before publishing the manifest:

```sh
mkdir -p verify-v4
for pack in no.blogspot.RawCull.models.clip-datacomp no.blogspot.RawCull.models.sam3; do
  curl --fail --location --retry 3 \
    "https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v4/$pack" \
    --output "verify-v4/$pack" || exit 1
  cmp "release-v4/$pack" "verify-v4/$pack" || exit 1
done
shasum -a 256 verify-v4/no.blogspot.RawCull.models.clip-datacomp \
  verify-v4/no.blogspot.RawCull.models.sam3
```

A private draft may require authenticated release downloads; independently test
the final public URLs without credentials because app clients need access.
After manifest publication, download `v4/manifest.json` with `curl --fail
--location`, compare it with the generated file, and inspect every pack's ID,
version, size, hosting configuration, policy, and URL. Keep checksum evidence
outside the archives, for example in a release `SHA256SUMS` file. Never publish
placeholder hashes or copy the v3 digests merely because filenames are unchanged.

## 10. If v4 introduces a genuinely new model

An updated compatible DataComp or SAM 3 export normally keeps its existing ID,
resource directory, and provider. A different selectable model needs more than
a new manifest entry:

1. Add a stable `RawCullAIModelDownloadID`, descriptor in `prepared`, inclusion
   flag and `downloadIDs` mapping. Add the corresponding selection enum case,
   display/resource names, and paths in `RawCullAIModels.swift`. Preserve persisted
   raw values for existing selections.
2. Add the model's provider/factory in PhotoAIKit if the architecture is not
   supported. Validate preprocessing, input shapes and names, output contracts,
   tokenizer, precision, and bundle metadata against that exact dependency pin.
   A renamed model file does not establish compatibility.
3. Wire the resource manager, managed-location mapping, provider selection,
   capability reporting, and applicable similarity/semantic-search/segmentation
   workflows in `RawCullAIIntegration.swift`. Review exhaustive switches and
   Settings selection/default handling across the repository.
4. Add the stable pack ID/source/destination to the developer template and the
   generated release manifest. Add notices/provenance and bundled licence text,
   then record all evidence and acceptance requirements in the descriptor.
5. Update the provenance parser if needed: it derives model mappings from enum
   names and literal inclusion flags. Extend its negative tests so missing or
   mismatched evidence still fails closed.
6. Extend catalog, release-metadata, provider, selection, download, and inference
   tests for the new model. Verify that embedding/mask caches distinguish the
   new model identity and do not reuse incompatible artifacts. If PhotoAIKit's
   pin changes, update the package-pin table in `README.md` as required by
   `ReleaseMetadataTests`.

Before rollout, exercise fresh install, v3-to-v4 upgrade, restart, explicit
licence acceptance where required, cancellation/retry, removal/redownload,
invalid bundle rejection, CLIP image similarity and text search, and SAM 3 Deep
Review with representative photos. Record the loaded path, fingerprint,
quality results, memory use, and latency. Keep v3 available for existing app
builds. If v4 is defective, publish corrected assets under a later tag and
monotonically newer pack versions rather than overwriting v4; do not assume a
manifest downgrade will replace a cached newer pack.
