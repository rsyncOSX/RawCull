# Publishing new RawCull AI models

This runbook describes how to publish a new self-hosted Managed Background
Assets release and enable its models in RawCull. The examples use a lowercase
`v2` Git tag in the
[`RawCull-AI-Models`](https://github.com/rsyncOSX/RawCull-AI-Models/releases)
repository. Git tag names and GitHub release URLs are case-sensitive: if the
actual tag is `V2`, use `V2` everywhere instead of `v2`.

The intended `v2` release contains exactly these three optional models:

| Model | Asset-pack ID | Installed destination |
|---|---|---|
| DataComp CLIP | `no.blogspot.RawCull.models.clip-datacomp` | `Models/CLIP-DataComp` |
| OpenAI CLIP | `no.blogspot.RawCull.models.clip-openai` | `Models/CLIP-OpenAI` |
| Meta SAM 3 | `no.blogspot.RawCull.models.sam3` | `Models/SAM3` |

EfficientSAM must not be added to the release manifest, production download
catalog, or AI settings.

## 1. Clear the release blockers first

Do not mark a model as release-ready merely because its converted files work
locally. Resolve and record the licence, provenance, and redistribution
requirements before publishing it.

### OpenAI CLIP

Before enabling the OpenAI CLIP download:

1. Identify the exact immutable upstream checkpoint revision.
2. Record the source weight filename and its SHA-256 checksum.
3. Establish that the licence terms cover redistribution of the exact model
   weights, not only the OpenAI CLIP source code and tokenizer.
4. Record how that checkpoint was converted into the shipped `.aimodel`.
5. Record a reproducible fingerprint of the converted model directory.
6. Include all required licence and attribution files in the asset pack.
7. Update `ModelAssets/Notices/CLIP-OpenAI/NOTICE.md` and
   `ModelAssets/Notices/CLIP-OpenAI/PROVENANCE.json` with the verified facts.

### SAM 3

Before enabling the SAM 3 download:

1. Identify the exact immutable upstream checkpoint revision.
2. Record the source weight filename and its SHA-256 checksum.
3. Confirm that distributing the converted model through an ungated GitHub
   release is compatible with Meta's SAM License and the official gated model
   access flow.
4. Record the conversion tool, version, source revision, and converted model
   fingerprint.
5. Include the complete SAM License and required notices in the asset pack.
6. Keep explicit in-app licence acceptance enabled for SAM 3.
7. Update `ModelAssets/Notices/SAM3/NOTICE.md` and
   `ModelAssets/Notices/SAM3/PROVENANCE.json` with the verified facts.

If either legal review is unresolved, leave that descriptor blocked and omit
that pack from the published manifest. A release tag does not by itself clear
a redistribution blocker.

## 2. Prepare the three staging directories

Use `ModelAssets/manifest.template.json` as the source/destination map. Prepare
the release staging tree with these source directories:

```text
CLIP-DataComp/
CLIP-OpenAI/
SAM3/
```

Each directory must contain the complete converted model bundle and everything
needed by its runtime, such as tokenizer resources. Include the matching notice
catalog with each redistributed pack:

```text
Notices/CLIP-DataComp/
Notices/CLIP-OpenAI/
Notices/SAM3/
```

Before packaging, verify that the model locations produced by the manifest
match the paths expected by `RawCullAIModelDownloadCatalog.production`:

```text
Models/CLIP-DataComp
Models/CLIP-OpenAI
Models/SAM3
```

Do not rename an asset-pack ID or destination without making the same change
in the manifest template, RawCull catalog, documentation, and release tests.

## 3. Generate the Managed Background Assets release

Using the Managed Background Assets tools from the release version of Xcode:

1. Generate the deployable asset-pack archives from the staging directories.
2. Generate `manifest.json` from `ModelAssets/manifest.template.json`.
3. Confirm that the generated manifest contains all three asset-pack IDs.
4. Confirm that every file URL in the generated manifest points to the files
   that will be attached to the `v2` GitHub release.
5. Retain the generated archive checksums and exact byte counts for the RawCull
   catalog and audit records.

For every published archive, record at least:

```sh
shasum -a 256 /path/to/archive
stat -f '%z' /path/to/archive
```

The first command gives `expectedArchiveSHA256`; the second gives
`downloadByteCount`. Set `installedByteCount` from the packaging output when an
exact extracted size is available; otherwise it may remain `nil`.

`expectedArchiveSHA256` is currently catalog/audit metadata. Runtime transfer
integrity is enforced by the generated Managed Background Assets manifest, so
the integrity information inside that manifest must also be correct.

## 4. Publish the `v2` GitHub release safely

Create the `v2` release in `RawCull-AI-Models`, then publish in this order:

1. Upload every generated asset-pack archive.
2. Verify that each archive can be downloaded over HTTPS.
3. Compare every downloaded archive's SHA-256 and byte count with the recorded
   local values.
4. Upload `manifest.json` last. This prevents clients from seeing a manifest
   that refers to missing archives.
5. Verify the final manifest URL:

```sh
curl --fail --location --output /tmp/rawcull-v2-manifest.json \
  https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v2/manifest.json
jq empty /tmp/rawcull-v2-manifest.json
```

6. Inspect the downloaded manifest and verify these IDs and destinations:

```text
no.blogspot.RawCull.models.clip-datacomp -> Models/CLIP-DataComp
no.blogspot.RawCull.models.clip-openai  -> Models/CLIP-OpenAI
no.blogspot.RawCull.models.sam3         -> Models/SAM3
```

Do not update RawCull to `v2` until the final manifest and every referenced
archive are reachable from a clean, unauthenticated HTTPS request.

## 5. Enable all three models in RawCull

In
`RawCull/Model/AIIntegration/RawCullAIModelDownloadCatalog.swift`, set the
code-only inclusion switches to:

```swift
nonisolated enum RawCullAIModelInclusion {
    static let includeOpenAICLIP = true
    static let includeDataCompCLIP = true
    static let includeSAM3 = true

    // Existing computed properties remain unchanged.
}
```

At the time this runbook was written, OpenAI CLIP was disabled. DataComp CLIP
and SAM 3 were enabled for presentation, although SAM 3 remained
release-blocked.

These switches control both the AI settings UI and the production model
download catalog. When both CLIP models are included, RawCull shows the CLIP
model picker. SAM 3 remains the only presented segmentation model.

## 6. Update the production catalog descriptors

In `RawCullAIModelDownloadCatalog.production`, update each archive that was
rebuilt for `v2`, including DataComp CLIP. Use the actual release values:

```swift
upstreamRevision: "<immutable upstream revision>",
expectedArchiveSHA256: "<64-character lowercase archive SHA-256>",
downloadByteCount: <exact archive size in bytes>,
installedByteCount: <exact installed size in bytes or nil>,
releaseReadiness: .ready,
```

### OpenAI CLIP descriptor

Replace the placeholder or blocked metadata with verified values:

```swift
upstreamRevision: "<verified OpenAI checkpoint revision>",
expectedArchiveSHA256: "<OpenAI CLIP archive SHA-256>",
downloadByteCount: <OpenAI CLIP archive bytes>,
installedByteCount: <OpenAI CLIP installed bytes or nil>,
releaseReadiness: .ready,
```

Also replace `Licence verification pending` and its blocked summary with the
verified licence name, source URL, and accurate redistribution summary. Ensure
`bundledTextResourceName` names the complete verified text actually packaged
in `RawCull/Resources/ModelLicences`, and update `textSHA256` if that text
changes.

OpenAI CLIP does not currently require interactive acceptance. Change
`requiresExplicitAcceptance` only if the verified licence requires it.

### SAM 3 descriptor

Replace the blocked metadata with verified values:

```swift
upstreamRevision: "<verified SAM 3 checkpoint revision>",
expectedArchiveSHA256: "<SAM 3 archive SHA-256>",
downloadByteCount: <SAM 3 archive bytes>,
installedByteCount: <SAM 3 installed bytes or nil>,
releaseReadiness: .ready,
```

Keep these SAM 3 licence settings unless Meta publishes superseding terms:

```swift
bundledTextResourceName: "SAM3-SAM-License-2025-11-19",
textSHA256: "b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab",
requiresExplicitAcceptance: true,
```

If the licence text or version changes, add the new complete text to
`RawCull/Resources/ModelLicences`, update the resource name and checksum, and
update the notice/provenance files. Changing the verified licence checksum
correctly invalidates acceptances recorded for the older text.

### DataComp CLIP descriptor

DataComp CLIP is already marked `.ready`. If `v2` republishes a newly generated
archive, replace its existing `expectedArchiveSHA256` and `downloadByteCount`
with the new archive values. Keep the existing immutable upstream revision only
if `v2` uses the same source checkpoint.

## 7. Point both download configurations to `v2`

RawCull currently stores the production manifest URL in two places. They must
remain identical.

In `RawCull/Model/AIIntegration/RawCullAIModelDownloadService.swift`:

```swift
static let productionManifestURL = URL(
    string: "https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v2/manifest.json",
)!
```

In `RawCull-Info.plist`:

```xml
<key>BAManifestURL</key>
<string>https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v2/manifest.json</string>
```

Keep `BAUsesAppleHosting` set to `false` for the GitHub-hosted release. The
existing download-domain allowlist already covers `github.com` and
`*.githubusercontent.com`.

## 8. Finalize provenance and model documentation

Update all relevant files below `ModelAssets/Notices`:

1. Set `release_status` to `ready` only after its blocker is resolved.
2. Remove `release_blocker`, make it optional, or replace it with a field that
   records the completed release review. Keep the JSON schema and tests in
   agreement.
3. Record the immutable source revision and source-weight checksum.
4. Record the converted model fingerprint.
5. Record the downloadable archive checksum and byte count.
6. Update each `NOTICE.md` so it no longer says that a released model remains
   blocked.
7. Verify the checksum of every referenced licence file.

Update `ModelAssets/README.md`:

1. Change the documented manifest URL from `/v1/manifest.json` to
   `/v2/manifest.json`.
2. Mark all three packs available and record their release checksums.
3. Remove statements saying that only DataComp is published.
4. Keep the warning that archives must be uploaded before the manifest.

## 9. Update the tests to describe the new release

### `RawCullAIModelDownloadsTests.swift`

Update `Production catalog includes only configured models` so it verifies:

```swift
#expect(catalog.models.map(\.id) == [
    .clipDataComp,
    .clipOpenAI,
    .sam3,
])
#expect(catalog.models.allSatisfy { $0.releaseReadiness.isReady })
```

Add exact assertions for each model's published archive SHA-256 and download
byte count. Continue verifying every bundled licence text against its recorded
`textSHA256`.

### `ReleaseMetadataTests.swift`

Update the release-metadata expectations:

1. Expect the `v2` URL in `RawCull-Info.plist`.
2. Expect `ModelAssets/README.md` to document `/v2/manifest.json`.
3. Change the expected count of `expectedArchiveSHA256: nil` from `2` to `0`
   when all three archives have recorded checksums.
4. Change the expected count of `releaseReadiness: .blocked` from `2` to `0`.
5. Rename and update the provenance test so released packs are expected to be
   `ready` rather than `blocked`.
6. If `release_blocker` becomes optional or is removed, update
   `ModelProvenance` in the test accordingly.
7. Add or update bundled licence checksum expectations when any licence file
   changes.

Do not weaken the tests merely to accommodate missing evidence. Fill in the
release metadata first, then make the expectations exact.

## 10. Build and test

Run the focused suites first:

```sh
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  -only-testing:RawCullTests/RawCullAIModelDownloadsTests \
  test

xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  -only-testing:RawCullTests/ReleaseMetadataTests \
  test
```

Then run the full test suite:

```sh
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  test
```

## 11. Perform a clean-machine download test

Before shipping RawCull with the `v2` URL:

1. Use a Mac or test account without previously installed RawCull model packs.
2. Open **Settings > AI** and confirm that only DataComp CLIP, OpenAI CLIP, and
   SAM 3 are listed.
3. Open **Download AI Models** and confirm that all three models are available.
4. Download DataComp CLIP and verify similarity and semantic search.
5. Download OpenAI CLIP, select it, and verify similarity and semantic search.
6. Confirm that DataComp and OpenAI artifacts do not cross-load.
7. Review and accept the SAM 3 licence, then download SAM 3.
8. Verify SAM 3 Deep Review and subject-mask generation.
9. Quit and relaunch RawCull; verify that all installed states and selections
   persist.
10. Remove each managed model and verify that only its managed asset pack is
    removed.
11. Test an interrupted download and retry.
12. Confirm that an unavailable model still leaves Vision feature-print
    similarity as the safe fallback.

## 12. Release checklist

- [ ] OpenAI CLIP checkpoint redistribution rights are verified.
- [ ] SAM 3 ungated redistribution is verified against the SAM License and
      gated-access requirements.
- [ ] Exact upstream revisions and source-weight checksums are recorded.
- [ ] Converted model fingerprints are recorded.
- [ ] All required licences and notices accompany every pack.
- [ ] All three generated archives are uploaded to the `v2` release.
- [ ] Archive SHA-256 values and exact byte counts match the catalog.
- [ ] `manifest.json` was uploaded after the archives.
- [ ] The production manifest works through unauthenticated HTTPS.
- [ ] The generated manifest contains exactly the three intended asset packs.
- [ ] All three inclusion flags are `true`.
- [ ] OpenAI CLIP and SAM 3 are marked `.ready` only after review.
- [ ] Both RawCull manifest URLs point to the exact `v2` tag.
- [ ] Notice, provenance, README, and tests describe the `v2` release.
- [ ] Focused and full test suites pass.
- [ ] Clean-machine download, relaunch, removal, and fallback tests pass.

## Rollback

If `v2` fails after RawCull has been updated but before the app is shipped,
restore both manifest URLs to the last known-good release and restore the model
catalog readiness values. Do not delete or replace assets under an existing Git
tag: publish a corrected immutable tag such as `v2.0.1`, verify it, and update
both RawCull URLs to that exact tag.
