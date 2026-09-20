# Apple-hosted Background Assets migration status and release plan

RawCull's application-side migration to Apple-hosted Managed Background Assets
is implemented. The three archives are packaged, measured, uploaded, and fully
processed by App Store Connect. Their internal beta releases are ready for
testing. The App Store build selects Apple hosting, while the ordinary
Release/Developer ID build keeps the existing self-hosted path. Creating and
uploading the signed App Store archive and completing TestFlight verification
remain release operations.

## Current implementation status

Status recorded on September 17, 2026:

| Area | Status | Evidence or remaining work |
|---|---|---|
| Three `.aar` archives generated and measured | **Completed** | CLIP, SAM 3, and Qwen archive byte counts and SHA-256 values are recorded below. |
| Packaging-manifest IDs, destinations, platform, and policy | **Completed** | The three IDs are unique and match RawCull. Every manifest contains exactly `"platforms": ["macOS"]` and `"downloadPolicy": {"onDemand": {}}`. |
| `ba-package evaluate` inventory comparison | **Completed** | All three manifests evaluate successfully with release `ba-package 2.0` outside the restricted workspace environment: 14 CLIP files, 11 SAM files, and 17 Qwen files. |
| Dedicated App Store build configuration | **Completed** | The app and downloader extension have an `AppStore` configuration with `RAWCULL_APPLE_HOSTED_MODEL_ASSETS`. `make archive-app-store` and App Store export options were added. |
| Apple-hosted app metadata | **Completed** | `RawCull-AppStore-Info.plist` contains only `BAAppGroupID`, `BAHasManagedAssetPacks`, and `BAUsesAppleHosting` from the Background Assets key family. It omits the GitHub manifest and restrictions. |
| Downloader host/protocol selection | **Completed** | App Store builds select `.appleHosted` and `StoreDownloaderExtension`; ordinary Release builds retain `.selfHosted` and `ManagedDownloaderExtension`. Both configurations build successfully. |
| Production model catalog | **Completed** | CLIP, SAM 3, and Qwen use the final pack IDs, model paths, archive sizes, and SHA-256 values. |
| Managed Qwen runtime and Settings UI | **Completed** | Downloaded Qwen activates automatically by default. A user-selected custom folder remains an explicit override, with cancellation-safe validation and source switching. |
| Repository manifest, provenance, and release documentation | **Completed for the Apple-hosted records** | The manifest template, all three `PROVENANCE.json` files, `ModelAssets/README.md`, verification scripts, Apple record/version UUIDs, processing dates, and this evidence table are updated. |
| Automated verification | **Completed for the implemented migration** | Provenance verification, provenance mutation tests, focused model-download/release-metadata tests, App Store build, Release build, plist validation, and `git diff --check` passed. |
| App Store Connect asset-pack records | **Completed** | Permanent records were created for `rawcull-clip-datacomp`, `rawcull-sam3`, and `rawcull-qwen3-vl-2b`. |
| Upload pack versions to App Store Connect | **Completed** | Version 1 of CLIP, SAM 3, and Qwen uploaded with zero errors and zero warnings. All three report `COMPLETE` for `MAC_OS`. |
| Internal beta asset releases | **Completed** | All three Apple-created internal beta releases report `READY_FOR_TESTING`. |
| Release version and build number | **Completed** | RawCull and its downloader extension use marketing version `3.2.4` and build `371` across all three configurations. |
| Signed App Store archive and upload | **Pending** | Requires App Store distribution credentials/profiles. |
| TestFlight validation | **Pending** | Perform the clean-install and download tests in section 18 after all three packs are Ready for Testing. |

The repository provenance records `processing_status` as `succeeded` and the
internal beta state as `ready-for-testing`. App Review remains correctly marked
`not-submitted` until the packs are added to a review submission.

The three intended production packs are:

| Model | Stable asset-pack ID | Packaged model path | Current archive |
|---|---|---|---|
| DataComp CLIP | `rawcull-clip-datacomp` | `Models/CLIP-DataComp` | `/Users/thomas/ModelAssets/Release/Output/clip-datacomp.aar` |
| Meta SAM 3 | `rawcull-sam3` | `Models/SAM3` | `/Users/thomas/ModelAssets/Release/Output/sam3.aar` |
| Qwen3-VL-2B-Instruct | `rawcull-qwen3-vl-2b` | `Models/Qwen/qwen3_vl_2b` | `/Users/thomas/ModelAssets/Release/Output/qwen3-vl-2b.aar` |

Current archive measurements, recorded on September 17, 2026:

| Archive | Bytes | SHA-256 |
|---|---:|---|
| `clip-datacomp.aar` | 282,967,354 | `994939e74dbbe9844214d509267642939f5ddc535ae3bce4be36c8855bdfa600` |
| `sam3.aar` | 1,542,689,931 | `08c9a4f58242d6eecaa322d65521fd788589ea682aa92a5cea03fa1e2f2681d4` |
| `qwen3-vl-2b.aar` | 3,754,599,603 | `115eebbfdff7cb688b26dd6e2dd6c110b3fce5d27f6d5e8f40f69192d1ca2364` |

These values are evidence for the current files only. Regenerating any archive,
including merely changing a notice inside it, requires recording a new byte
count and SHA-256.

## 0. Release and distribution decisions — completed

### Marketing version and build number — completed

The version gate is resolved as `MARKETING_VERSION = 3.2.4` and
`CURRENT_PROJECT_VERSION = 371`. The RawCull app and downloader extension use
those values consistently in Debug, Release, and AppStore configurations.

### Preserve separate distribution configurations — completed

Apple-hosted Background Assets are available only to apps installed through
TestFlight or the App Store. RawCull's existing Developer ID/notarized DMG cannot
rely on Apple-hosted packs.

The repository now has two explicit distribution paths:

- **AppStore configuration:** Apple-hosted packs, used by TestFlight and Mac App
  Store builds.
- **Direct/DeveloperID configuration:** retain self-hosted packs, or deliberately
  disable managed downloads and explain that models require the Mac App Store
  build. Do not accidentally ship `BAUsesAppleHosting = YES` in a DMG build.

The implemented `AppStore` Xcode build configuration is derived from Release.
It avoids making the existing `make build` Developer ID workflow silently
incompatible.

## 1. Prerequisites — partially completed

- Use the release version of Xcode 27 and its `ba-package` tool. Do not submit
  archives created by a beta packaging tool for App Store review.
- Confirm that the App Store Connect app is RawCull, bundle ID
  `no.blogspot.RawCull`, numeric Apple ID `6759362764`.
- Use an App Store Connect account with Account Holder, Admin, App Manager, or
  Developer access for uploads. App Review submission requires Account Holder,
  Admin, or App Manager access.
- Confirm the app and downloader extension both have the App Group
  `group.no.blogspot.RawCull.model-assets` in their identifiers, profiles, and
  entitlements.
- Confirm the model redistribution decisions, licences, notices, upstream
  revisions, and conversion evidence. Apple hosting changes the delivery host;
  it does not resolve model-licence obligations.
- Treat the three asset-pack IDs above as permanent. App Store Connect uses the
  app plus asset-pack ID as the pack identity. Archiving a pack removes all of
  its versions and the ID cannot be reused.

Apple currently allows 200 packs and 200 GB of compressed asset packs per app,
shared across platforms. These three packs are comfortably inside those limits:

- [Creating managed asset packs](https://developer.apple.com/documentation/backgroundassets/creating-managed-asset-packs)
- [Apple-hosted asset-pack limits](https://developer.apple.com/help/app-store-connect/reference/app-uploads/apple-hosted-asset-pack-size-limits)
- [Uploading Apple-hosted asset packs](https://developer.apple.com/help/app-store-connect/manage-asset-packs/upload-apple-hosted-asset-packs)

## 2. Clean and freeze the release inputs — completed

The release inputs were reconciled before packaging. The staging provenance is
host-correct for Apple delivery, SAM 3 is recorded as ready with its verified
licence evidence, and the frozen inputs produced the processed version 1
archives documented below.

For each pack:

1. Copy the matching notice and licence set from the audited RawCull repository
   into the release staging tree.
2. Make distribution wording host-neutral or explicitly state that the archive
   is delivered as an Apple-hosted asset pack.
3. Preserve immutable upstream revision and source checksum evidence.
4. Confirm that every licence filename and checksum in `PROVENANCE.json` matches
   the file included in the pack.
5. Do not put the final archive's own checksum into the provenance copy that is
   included inside that archive. That creates a self-referential checksum. Keep
   a frozen in-pack provenance record and add the final archive hash and size to
   the repository/external release record after packaging.
6. Remove Finder metadata and other unintended files from selected directories.
   The current selectors are narrow, but directory selectors must be inspected.
7. Freeze the source tree before packaging. If any selected byte changes,
   regenerate and remeasure the archive.

The source manifests are:

```text
/Users/thomas/ModelAssets/Release/Packaging/clip-datacomp.json
/Users/thomas/ModelAssets/Release/Packaging/sam3.json
/Users/thomas/ModelAssets/Release/Packaging/qwen3-vl-2b.json
```

Verify that their identifiers and selected model roots remain exactly:

```text
rawcull-clip-datacomp -> Models/CLIP-DataComp
rawcull-sam3          -> Models/SAM3
rawcull-qwen3-vl-2b  -> Models/Qwen/qwen3_vl_2b
```

All three should remain `onDemand`; none of these multi-gigabyte models should
be essential or automatically fetched during installation.

## 3. Evaluate and regenerate the `.aar` files — completed

From the asset source root:

```bash
cd /Users/thomas/ModelAssets/Release

xcrun ba-package evaluate Packaging/clip-datacomp.json
xcrun ba-package evaluate Packaging/sam3.json
xcrun ba-package evaluate Packaging/qwen3-vl-2b.json
```

Review every path printed by `evaluate`. The output must contain only the
intended model, tokenizer, metadata, licence, notice, and provenance files.

If the installed Xcode tool insists that the manifest be named `Manifest.json`,
evaluate/package one pack at a time from a temporary staging directory with
that filename. Do not change selector-relative paths when doing so.

Generate fresh archives:

```bash
xcrun ba-package package Packaging/clip-datacomp.json \
  --output-path Output/clip-datacomp.aar --verbose

xcrun ba-package package Packaging/sam3.json \
  --output-path Output/sam3.aar --verbose

xcrun ba-package package Packaging/qwen3-vl-2b.json \
  --output-path Output/qwen3-vl-2b.aar --verbose
```

Do not use `Output/manifest.json` for Apple hosting. That is the third-party
self-hosted download manifest with GitHub URLs. With Apple hosting, App Store
Connect owns the server-side manifest and versions.

## 4. Verify the generated files before upload — completed

Record exact logical sizes and checksums:

```bash
stat -f '%N|%z' /Users/thomas/ModelAssets/Release/Output/*.aar
shasum -a 256 /Users/thomas/ModelAssets/Release/Output/*.aar
```

Release evidence recorded on September 17, 2026:

| Evidence | DataComp CLIP | Meta SAM 3 | Qwen3-VL-2B-Instruct |
|---|---|---|---|
| Asset-pack ID | `rawcull-clip-datacomp` | `rawcull-sam3` | `rawcull-qwen3-vl-2b` |
| App Store Connect record ID | `a8bddf62-acbd-491f-87e0-8163661c0d2a` | `e3c32c84-1afb-4f1d-abb1-548ca9e0bc69` | `dd9484c0-ca1f-41cb-b566-3356b4a461fd` |
| Apple-assigned pack version | `1` | `1` | `1` |
| App Store Connect version ID | `120982fd-5a02-455f-bc9a-576ea290efca` | `93b2e488-855c-45c7-af3a-a3f1512fcf19` | `68d19be0-c04d-4897-b32c-b962211663ad` |
| Processing state | `COMPLETE` (`MAC_OS`) | `COMPLETE` (`MAC_OS`) | `COMPLETE` (`MAC_OS`) |
| Internal beta release ID | `3fa7254f-4dac-4c9d-9ae4-793ae3fb7d56` | `68a43f68-ad0d-484a-9242-e7aa57793043` | `61758a66-d648-4880-8bb6-a41d63c65334` |
| Internal beta state | `READY_FOR_TESTING` | `READY_FOR_TESTING` | `READY_FOR_TESTING` |
| Archive filename | `clip-datacomp.aar` | `sam3.aar` | `qwen3-vl-2b.aar` |
| Exact byte count | `282967354` | `1542689931` | `3754599603` |
| SHA-256 | `994939e74dbbe9844214d509267642939f5ddc535ae3bce4be36c8855bdfa600` | `08c9a4f58242d6eecaa322d65521fd788589ea682aa92a5cea03fa1e2f2681d4` | `115eebbfdff7cb688b26dd6e2dd6c110b3fce5d27f6d5e8f40f69192d1ca2364` |
| Xcode version and build number | Xcode 27.0 (`27A266a`) | Xcode 27.0 (`27A266a`) | Xcode 27.0 (`27A266a`) |
| `xcrun ba-package --version` output | `2.0` | `2.0` | `2.0` |
| Packaging-manifest SHA-256 | `f29941a49f84ad57bf79e92aad96bdcbde1de206653cae576903738ceae6ec3b` | `c6264450e9ac322fd7212a596b6b374836954933dd7a81f5e213bdbe3dcf9658` | `d558ce3b1768661c3694d88d47d5e65b1fd95d0a3f1d323c6d68e90384e38dfb` |
| Converted-model tree fingerprint (`directory-tree-sha256-v1`) | Main: `6a3639a2049b8a4ea23fe04c3083e199a4f505433f7c8bd0748b3c8d4fcb1572` | Main: `fc1cf6197f2b201f2dd3d45de28e8fcb1d29480a8a3ff430dc6d398d2071f9f2` | Embed: `907a07282d20d9371ef68118056b1e878462b65878279b969f74d2309fa81418`<br>Language: `ce950fc0991a7d1129a5f87a8050f831030f0db0d10a29682bf6c803a9ef381a`<br>Vision: `7c8657a983683cedfc289d8725b7ca10c3f2f0692e2b3d2e324ce21a4cc786d1` |
| Upstream model revision and source checksum | Revision: `4afec35ffe57a943d569ff7ee888061830164da8`<br>Source-weight checksum: unavailable in provenance | Revision: `3c879f39826c281e95690f02c7821c4de09afae7`<br>`model.safetensors`: `6d06f0a5f84e435071fe6603e61d0b4cc7b40e0d39d487cfd4d67d8cc11cc14a` | Revision: `78448d793a7eb2f7a987a1da76d464384aa1becd`<br>Source-weight checksum: unavailable in provenance |
| Licence/notice SHA-256 | `NOTICE.md`: `e34549a667382e9937bfdf6916c4dfdfbde81ba8b159346554e9fecdbc49f561`<br>`OpenCLIP-DataComp-MIT.txt`: `6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986`<br>`OpenAI-CLIP-Tokenizer-MIT.txt`: `893951b3bf94db8df1b13e05da5cdeb499400960e4d44a3962a8b33ed0b4f28e`<br>`Apple-coreai-models-BSD-3-Clause.txt`: `6762cc4b6772662c50c4c666dafbb2d0c97c80d6d54c9d628480ab59d655cf6e` | `NOTICE.md`: `f1a1d38c4de286bfc198acb8d20e79f9db5040a242fa06bcfdff87da45b4548f`<br>`SAM3-SAM-License-2025-11-19.txt`: `b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab`<br>`OpenAI-CLIP-Tokenizer-MIT.txt`: `893951b3bf94db8df1b13e05da5cdeb499400960e4d44a3962a8b33ed0b4f28e`<br>`Apple-coreai-models-BSD-3-Clause.txt`: `6762cc4b6772662c50c4c666dafbb2d0c97c80d6d54c9d628480ab59d655cf6e` | `NOTICE.md`: `b3b0f99f0a8c839b7b9fc76eec29ba1d7440ca56256accddae5cfe79d7c5ea79`<br>`Qwen3-VL-Apache-2.0.txt`: `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`<br>`Apple-coreai-models-BSD-3-Clause.txt`: `6762cc4b6772662c50c4c666dafbb2d0c97c80d6d54c9d628480ab59d655cf6e` |
| Packaging date | September 17, 2026 | September 17, 2026 | September 17, 2026 |
| Release decision made by | Thomas Evensen | Thomas Evensen | Thomas Evensen |

Then perform these checks:

1. Re-run `ba-package evaluate` and compare its file list with the frozen input
   inventory.
2. Verify the three IDs are unique and identical to the IDs that RawCull will
   request.
3. Confirm the archive is generated for `macOS` and policy is `onDemand`.

Verification results recorded on September 17, 2026:

| Check | Result | Evidence |
|---|---|---|
| `ba-package evaluate` file-list comparison | **Passed** | `ba-package 2.0` from Xcode 27.0 (`27A266a`) evaluated all three manifests successfully outside the restricted workspace environment. It selected 14 CLIP files, 11 SAM files, and 17 Qwen files; none is a symbolic link or `.DS_Store` file. The selected lists match the packaged model, tokenizer, notice, licence, and provenance inventory. |
| Asset-pack ID uniqueness and RawCull match | **Passed** | The manifest IDs are unique, conform to Apple's permitted character set, and exactly match RawCull's production download catalog: `rawcull-clip-datacomp`, `rawcull-sam3`, and `rawcull-qwen3-vl-2b`. The managed Qwen location is now selected automatically when its pack is installed, while a user-selected custom Qwen bundle remains available as an explicit override. |
| Platform and download policy | **Passed** | All three packaging manifests contain exactly `"platforms": ["macOS"]` and `"downloadPolicy": {"onDemand": {}}`. |

4. Verify the expected installed root exists in the selected source tree.
5. Run RawCull's provenance verification after updating the repository copies:

   ```bash
   cd /Users/thomas/GitHub/RawCull/RawCull
   python3 Scripts/VerifyModelProvenance.py
   python3 Scripts/TestModelProvenance.py
   ```

6. Keep the final archives immutable. If an upload must be replaced, package a
   new version rather than modifying an already processed version.

## 5. Upload the packs to App Store Connect — completed

### Preferred first upload: Transporter

1. Install/open Apple's Transporter app and sign in with the App Store Connect
   account.
2. Deliver `clip-datacomp.aar` first. Its small size makes it the quickest way
   to validate identifiers, permissions, packaging-tool compatibility, and the
   App Store Connect workflow.
3. Wait for processing to complete; do not immediately upload all three if the
   first pack fails validation.
4. Confirm that the processed record belongs to RawCull and has exactly
   `rawcull-clip-datacomp`.
5. Upload and verify `sam3.aar`.
6. Upload and verify `qwen3-vl-2b.aar`.
7. Save Transporter delivery logs with the release evidence.

Apple associates the ID inside each archive with RawCull's app record and
automatically assigns/increments the asset-pack version. The version shown in
App Store Connect is not RawCull's marketing version and is not the old
self-hosted manifest's `version: 3`.

### Command-line alternative

Never place credentials in the repository or shell history. Use an App Store
Connect API key or a securely stored app-specific password. Apple's documented
`altool` form is:

```bash
xcrun altool \
  --upload-asset-pack /Users/thomas/ModelAssets/Release/Output/clip-datacomp.aar \
  --apple-id 6759362764 \
  -u '<APP_STORE_CONNECT_ACCOUNT>' \
  -p '<APP_SPECIFIC_PASSWORD>'
```

Repeat for SAM 3 and Qwen only after the first upload processes successfully.
For repeatable CI, prefer the App Store Connect Background Assets API: create
the pack record, create a pack-version record, reserve the upload, upload all
parts, commit it, and poll processing state.

- [Background Assets API](https://developer.apple.com/documentation/appstoreconnectapi/background-assets)
- [Uploading and versioning Apple-hosted assets](https://developer.apple.com/documentation/appstoreconnectapi/managing-apple-hosted-background-assets)

## 6. Verify uploads in App Store Connect — processing completed; review pending

For every pack, record and check:

- RawCull is the associated app;
- exact asset-pack ID;
- automatically assigned pack version;
- processing status has succeeded;
- reported download size is plausible and corresponds to the local archive;
- internal beta release reaches **Ready for Testing**;
- no manifest, platform, licence, or packaging warnings appear; and
- the upload/delivery checksum returned by Apple's API or delivery log matches
  the uploaded local file where Apple exposes it.

Do not archive a pack merely to fix a version. Upload a new version under the
same correct ID. Archiving removes every beta and App Store version and makes
the ID unusable.

Uploading does not publish the packs to customers. It only makes processed
versions eligible for TestFlight and App Review.

## 7. Add an App Store build configuration — completed

An `AppStore` configuration derived from Release now exists for both the
RawCull app and `RawCullModelDownloader` extension.

For the AppStore configuration:

- add `RAWCULL_APPLE_HOSTED_MODEL_ASSETS` to
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for both targets;
- use App Store distribution signing/profiles;
- keep the app and extension build number and marketing version aligned;
- retain the shared App Group entitlement; and
- use an App Store export-options plist/method rather than the current
  Developer ID export/notarization workflow.

Keep Release/DeveloperID on the self-hosted configuration until a deliberate
decision is made for direct distribution.

Add a Makefile target such as `archive-app-store` that archives with the
`AppStore` configuration and exports/uploads the build. It must not run the
Developer ID notarization/DMG path.

## 8. Configure the Apple-hosted app metadata — completed

Apple says an Apple-hosted app should include only these Background Assets keys:

```text
BAAppGroupID = group.no.blogspot.RawCull.model-assets
BAHasManagedAssetPacks = YES
BAUsesAppleHosting = YES
```

Omit every other Background Assets key from the AppStore configuration,
including:

- `BAManifestURL`;
- `BAInitialDownloadRestrictions` and its GitHub domain allow-list;
- `BAEssentialMaxInstallSize`; and
- `BAMaxInstallSize`.

Because the existing `RawCull-Info.plist` must remain usable by the
DeveloperID/self-hosted configuration, use one of these approaches:

1. preferred for clarity: add `RawCull-AppStore-Info.plist`, keep the ordinary
   plist for self-hosting, and set `INFOPLIST_FILE` per configuration; or
2. generate the relevant Info.plist keys entirely from per-configuration build
   settings, ensuring the forbidden self-hosted keys are genuinely absent, not
   merely empty.

Do not leave `BAManifestURL` or GitHub restrictions in the Apple-hosted plist.
Apple explicitly instructs Apple-hosted apps to omit all other Background
Assets keys.

See [Downloading Apple-hosted asset packs](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs).

## 9. Switch the downloader extension by configuration — completed locally

`RawCullModelDownloader/RawCullModelDownloader.swift` already has both entry
points:

- `StoreDownloaderExtension` when
  `RAWCULL_APPLE_HOSTED_MODEL_ASSETS` is defined; and
- `ManagedDownloaderExtension` for self-hosting.

No behavioral implementation is required because all packs are on-demand and
RawCull accepts the default policy. Verify instead that:

- AppStore compiles the `StoreKit`/`StoreDownloaderExtension` branch;
- DeveloperID compiles the `BackgroundAssets`/`ManagedDownloaderExtension`
  branch;
- the extension is embedded in the app archive;
- both targets are signed by the same team with the same App Group; and
- the final built app contains exactly one extension entry point.

Add a release-metadata test or archive inspection that detects the selected
branch/build condition so a self-hosted extension cannot be shipped with an
Apple-hosted plist.

## 10. Select the correct source in application code — completed

Update
`RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift`.

Replace the hard-coded `.selfHosted(...)` in
`RawCullAIModelDownloadCoordinator.live` with a configuration-selected source:

```swift
nonisolated extension RawCullAIModelDownloadSource {
    static var live: Self {
        #if RAWCULL_APPLE_HOSTED_MODEL_ASSETS
            .appleHosted
        #else
            .selfHosted(manifestURL: liveManifestURL)
        #endif
    }
}
```

Then construct the service with `source: .live`.

Keep `.selfHosted` and its injected test URL so unit tests and the direct build
remain testable. The source value currently gates configuration while
`AssetPackManager` performs the common runtime work; the actual host is selected
by the plist and downloader-extension protocol.

Add tests proving:

- `.appleHosted.isConfigured` is true;
- the AppStore build selects `.appleHosted`;
- the direct build selects `.selfHosted`;
- source, plist, and extension protocol cannot disagree; and
- Xcode unit tests still avoid live Background Assets networking.

## 11. Add Qwen to the managed-download catalog — completed

Update
`RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift`.

### Stable ID and inclusion

Add:

```swift
case qwen3VL2B = "qwen3-vl-2b"
```

Update every exhaustive switch, including `clipModel`, so Qwen maps to `nil`.
Add `includeQwen3VL2B`/`includeQwen3VL2BDownload` or one clearly named flag and
insert the ID into `downloadIDs` for production.

### Qwen descriptor

Add a prepared, release-ready descriptor with:

- display name `Qwen3-VL-2B-Instruct`;
- purpose describing local vision-language photo analysis;
- publisher `Qwen Team / Alibaba Cloud` as supported by the source notices;
- immutable upstream revision
  `78448d793a7eb2f7a987a1da76d464384aa1becd`;
- resource name `Qwen`;
- asset-pack ID `rawcull-qwen3-vl-2b`;
- asset-pack model path `Models/Qwen/qwen3_vl_2b`;
- pinned upstream/model-card URLs;
- conversion source/revision information;
- SHA-256 and byte count of the newly regenerated archive;
- installed byte count measured from the selected installed tree;
- bundled `Qwen3-VL-Apache-2.0` licence and its verified SHA-256
  `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`;
- `requiresExplicitAcceptance: false` unless product/legal review intentionally
  requires an acceptance screen for Apache-2.0; and
- `.ready` only after Apple has processed the exact archive and the evidence is
  complete.

The production catalog should then be exactly:

```text
clipDataComp, sam3, qwen3VL2B
```

Do not add Qwen to `RawCullCLIPModel` or `RawCullSegmentationModel`; it is a
separate vision-language runtime.

## 12. Feed the managed Qwen location into the Qwen runtime — completed

All installed model locations now enter through
`RawCullAIModelRuntime.applyManagedModelLocations`. The runtime owns the Qwen
manager alongside the CLIP and SAM 3 resource managers, while the individual
actors retain their separate isolation domains.

Update `RawCullAISettingsModel.applyManagedModelLocations` to:

1. pass the complete location snapshot to
   `modelRuntime.applyManagedModelLocations`;
2. let the runtime update the CLIP and SAM 3 resource-manager actors;
3. let the runtime validate or clear its Qwen manager;
4. publish the returned Qwen status to `RawCullQwenAnalysisFeature`; and
5. refresh the remaining capability snapshot.

No security-scoped bookmark is needed for a URL returned by
`AssetPackManager`. Continue using security-scoped access only for a manually
selected external model directory.

### Qwen source precedence

Implement an explicit source preference rather than allowing two unrelated
paths to race during `refresh()`:

```text
1. User-selected custom model, when the user explicitly enables the override.
2. Installed managed Qwen pack.
3. No Qwen model configured.
```

Recommended persisted enum:

```swift
enum RawCullQwenModelSource: String, Codable, Sendable {
    case managed
    case custom
}
```

Default to `.managed`. If `.custom` is selected but its bookmark is missing or
invalid, show that error and provide a one-click action to return to the managed
model. Do not silently switch source while an analysis is running.

Centralize all activation in a method such as `reconcileQwenModelSource()`.
Both `refresh()` and `applyManagedModelLocations` should call this method. It
must cancel stale validation tasks and use a generation/token check so an older
custom validation cannot overwrite a newer managed result.

When switching from custom to managed:

- stop security-scoped access to the custom URL;
- keep the bookmark so the user can switch back later;
- validate the managed URL; and
- update `qwenModelStatus` and `qwenAnalysisFeature` together.

When removing the managed pack:

- apply a location snapshot without Qwen through `RawCullAIModelRuntime`, which
  clears its `QwenInferenceRuntime`;
- set an unavailable/not-configured state unless custom override is active; and
- prevent an in-flight Qwen analysis from retaining a provider backed by the
  removed path.

Consider extending `QwenInferenceServing` with a cancellation/reset operation if
`clear()` alone cannot safely stop an active model/session before pack removal.

## 13. Redesign the AI Settings presentation — completed

Update `RawCull/Views/Settings/AISettingsTab.swift` and
`RawCull/Views/Settings/AIModelDownloadsView.swift`.

### Download sheet

Once Qwen is in the production catalog, the existing `ForEach` automatically
adds a third row. Verify that it displays:

- `Qwen3-VL-2B-Instruct` and publisher;
- approximately 3.75 GB download size using the descriptor's byte count;
- on-demand state and progress;
- licence review;
- Download, Cancel, Retry, Reveal Location, and Remove behavior; and
- clear text that Qwen analysis remains local after installation.

Add user-facing size formatting if the row does not currently expose
`downloadByteCount`/`installedByteCount`. A 3.75 GB action should make its size
clear before the user starts it.

### Qwen settings card

Rename **Local Qwen** to **Qwen Vision Model** and replace the current assumption
that Qwen must always be selected manually.

The card should show:

- active source: `Downloaded by RawCull` or `Custom folder`;
- validation/model name;
- managed status: not downloaded, downloading, installed, invalid, or removed;
- **Manage Downloads** action that opens the shared model-download sheet;
- **Use Downloaded Model** when the managed pack is installed;
- **Choose Custom Model…** as an advanced override/fallback;
- **Validate Again** for the currently selected source;
- **Clear Custom Selection** without deleting a managed pack; and
- explanatory text that removing the Apple-managed model is done in the
  downloads sheet.

Do not label a managed Qwen model as a manually selected “local model.” It is
local at runtime, but its lifecycle is managed by Background Assets.

Change the file importer so choosing a folder sets source preference to
`.custom`. The normal 2.3.4/3.2.4 experience should require no file picker: the
user opens **Download AI Models**, downloads Qwen, and RawCull activates it.

### Refresh behavior

Currently `RawCullAISettingsModel.refresh()` starts managed-model refresh and
saved custom-Qwen activation concurrently. That can race once Qwen is managed.
Change the order:

1. refresh managed-model locations;
2. reconcile the selected Qwen source;
3. refresh capability/status presentation.

Preserve concurrency only for operations that cannot update the same Qwen
manager/status.

## 14. Update manifests, notices, and repository documentation — completed for release records

### Developer packaging template

Update `ModelAssets/manifest.template.json` to include the Qwen pack and
destination, even though Apple does not consume the repository's self-hosted
manifest. It remains the source-of-truth/integrity fixture for pack IDs and
paths.

Use a selector matching the actual Qwen package root:

```text
source: Qwen/qwen3_vl_2b
destination: Models/Qwen/qwen3_vl_2b
```

If the source template is intended only for self-hosted generation, document
that Apple receives the separately generated `.aar`, not
`ModelAssets/manifest.template.json` or `Output/manifest.json`.

### Provenance

Update:

- `ModelAssets/Notices/CLIP-DataComp/PROVENANCE.json`;
- `ModelAssets/Notices/SAM3/PROVENANCE.json`;
- `ModelAssets/Notices/Qwen/PROVENANCE.json`;
- their `NOTICE.md` files; and
- `ModelAssets/README.md`.

Replace GitHub release URLs with Apple-hosted distribution evidence that can be
verified from App Store Connect. Because Apple does not expose a normal public
asset URL, record the RawCull Apple ID, asset-pack ID, Apple-assigned version,
processing status/date, local archive checksum/size, and review state instead
of inventing an `asset_url`.

Evolve `Scripts/VerifyModelProvenance.py` and its schema/tests so release records
support both:

- legacy/self-hosted releases with tag and URL; and
- Apple-hosted releases with app ID, pack ID, pack version, archive hash/size,
  processing evidence, and review state.

Do not weaken verification merely because there is no public Apple URL.

### Documentation

Update:

- `ModelAssets/README.md` to describe Apple-hosted production and all three
  packs;
- `updateversionmodels.md` or replace it with an Apple-hosted release procedure;
- `README.md` to describe downloadable Qwen rather than manual-only Qwen; and
- direct-distribution documentation to explain whether the DMG remains
  self-hosted or lacks managed downloads.

## 15. Update tests — focused migration coverage completed

### `RawCullAIModelDownloadsTests.swift`

Update/add coverage for:

- production IDs equal `[.clipDataComp, .sam3, .qwen3VL2B]`;
- prepared IDs include Qwen in stable order;
- Qwen asset-pack ID/path, revision, hash, byte counts, licence hash, and
  readiness;
- `.appleHosted` configuration;
- all three states in a production snapshot;
- Qwen install/removal location propagation;
- cancellation and retry of the large Qwen download;
- managed Qwen requires no security-scoped bookmark; and
- removing Qwen clears/reconciles the Qwen provider.

Update synthetic helpers and exhaustive switches for the new enum case.

### Qwen tests

Extend `QwenFeatureTests.swift` or add focused settings-model tests for:

- managed pack automatically activates after successful download;
- custom override takes precedence only when explicitly selected;
- switching back to managed stops custom security-scoped access;
- a stale custom validation cannot overwrite a managed validation result;
- managed removal clears the provider;
- custom fallback still works when managed Qwen is not installed;
- relaunch restores source preference and validates the right URL; and
- active analysis reacts safely when the pack is removed or updated.

Use fakes for security-scoped access rather than relying on real sandbox
bookmarks in unit tests if necessary.

### `ReleaseMetadataTests.swift`

The stale version expectation is updated to the confirmed release version
`3.2.4`.

Add AppStore-configuration assertions:

- `BAAppGroupID` is correct;
- `BAHasManagedAssetPacks == true`;
- `BAUsesAppleHosting == true`;
- all other Background Assets keys are absent;
- `RAWCULL_APPLE_HOSTED_MODEL_ASSETS` is defined for app and extension;
- app and extension versions/builds match;
- Qwen is present in template/catalog/provenance;
- the Apple-hosted extension branch is selected; and
- AppStore export settings use App Store distribution.

Retain separate assertions for DeveloperID/self-hosted metadata.

Update the provenance decoding fixture to understand Apple-hosted release
records, and include `Qwen3-VL-Apache-2.0.txt` in bundled licence hash checks.

### UI and accessibility tests

Verify:

- all three rows are accessible by model name and state;
- multi-gigabyte sizes are spoken/read correctly;
- Qwen's managed/custom source is exposed in accessibility value;
- licence review works for each pack;
- progress, cancellation, retry, removal confirmation, and failure messages are
  accessible; and
- the model-download sheet remains usable at its fixed size with three rows.

## 16. Version 3.2.4 project changes — completed

RawCull and the downloader extension now use `MARKETING_VERSION = 3.2.4` and
`CURRENT_PROJECT_VERSION = 371`. Confirm those values inside the signed archived
app and embedded extension before upload:

```bash
plutil -p <archive>/Products/Applications/RawCull.app/Contents/Info.plist
plutil -p <archive>/Products/Applications/RawCull.app/Contents/Extensions/RawCullModelDownloader.appex/Contents/Info.plist
```

For an App Store-only release, do not run the Developer ID DMG/notarization
target as the distribution artifact for Apple-hosted assets.

## 17. Local verification before TestFlight — partially completed

Run formatting and repository checks:

```bash
swiftformat --config .swiftformat \
  RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift \
  RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadService.swift \
  RawCull/Intelligence/ModelManagement/RawCullAISettingsModel.swift \
  RawCull/Views/Settings/AISettingsTab.swift \
  RawCullTests/RawCullAIModelDownloadsTests.swift \
  RawCullTests/ReleaseMetadataTests.swift

python3 Scripts/VerifyModelProvenance.py
python3 Scripts/TestModelProvenance.py
make verify-ai-import-boundary
make test-smoke
```

Run focused tests while iterating:

```bash
xcodebuild test \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  -only-testing:RawCullTests/RawCullAIModelDownloadsTests \
  -only-testing:RawCullTests/QwenFeatureTests \
  -only-testing:RawCullTests/ReleaseMetadataTests
```

Archive the AppStore configuration and inspect it before upload:

```bash
xcodebuild archive \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -configuration AppStore \
  -destination 'generic/platform=macOS' \
  -archivePath build/RawCull-AppStore.xcarchive
```

Inspect the archive for:

- correct app/extension versions;
- App Store signing and profiles;
- shared App Group entitlements;
- embedded downloader extension;
- `BAUsesAppleHosting = YES`;
- absence of `BAManifestURL` and all other forbidden Background Assets keys;
- extension compiled as `StoreDownloaderExtension`; and
- no `.aar` or model payload accidentally embedded in the application bundle.

Apple recommends local mock-server testing before distribution. Use the
Managed Background Assets local testing tools to exercise the same IDs and
paths, but treat TestFlight as the authoritative Apple-hosted integration test.

## 18. Internal TestFlight verification — pending

Upload the AppStore build after all three packs show Ready for Testing. Install
the build through TestFlight on a clean supported Apple Silicon Mac.

Test from a clean installation:

1. Open AI Settings and confirm CLIP, SAM 3, and Qwen appear in the download
   sheet without a GitHub manifest request.
2. Confirm none downloads automatically.
3. Download CLIP; observe progress, validate installation, run similarity and
   semantic search, quit/relaunch, and verify it remains available.
4. Download SAM 3; review/accept its verified licence first, run Deep Review,
   quit/relaunch, and verify it remains available.
5. Download Qwen; verify the size is shown before download, progress remains
   responsive, it activates without a file picker, and vision-language analysis
   works after relaunch.
6. Cancel each download partway through, verify stable state, then retry.
7. Interrupt networking and relaunch; verify recovery/resumption and useful
   errors.
8. Remove each model independently and verify only that pack disappears.
9. Verify removing Qwen clears its provider and disables analysis safely.
10. Exercise custom Qwen override, switch back to downloaded Qwen, and verify
    precedence survives relaunch.
11. Upload a new internal-beta pack version under the same ID and verify
    `requireLatestVersion: true` updates it.
12. Confirm disk-space errors and low-space behavior do not corrupt installed
    packs.
13. Confirm Console contains no entitlement, app-group, StoreKit, extension, or
    asset-path errors.

Repeat critical download/remove/update tests on a second Mac and a non-admin
user account if available.

## 19. Review and release — pending

Asset packs must pass review before external TestFlight or App Store use.

Because RawCull already has an App Store record/release, packs may be submitted
with or without a new app version. For this migration, submit the three first
production pack versions together with the new RawCull app version so review
sees the complete feature and licence UI.

App Store Connect permits up to ten different asset packs in one submission, so
all three fit in a single submission.

Before submission:

- select the exact tested version of each pack;
- attach the confirmed RawCull marketing version/build;
- describe the AI models, their optional on-demand nature, local execution, and
  licence-review behavior in App Review notes;
- explain how reviewers reach AI Settings and download each pack;
- provide any required SAM licence/access explanation;
- confirm no user photographs are uploaded by the model-download feature; and
- retain the local archives and release evidence corresponding to the submitted
  versions.

See [Submitting Apple-hosted asset packs](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-apple-hosted-asset-packs).

## 20. Rollback strategy — defined

- Do not delete the GitHub v3 release or self-hosted support during the first
  Apple-hosted rollout.
- If the TestFlight build fails before review, upload a corrected pack version
  under the same ID and select that version for testing.
- If an app-code issue is found, ship a corrected app build pointing to the
  same known-good asset versions.
- Do not replace bytes within an existing processed pack version.
- Do not archive a pack as a routine rollback; archiving is destructive and its
  ID cannot be reused.
- Keep the previous App Store pack version available until the replacement has
  passed internal and external testing.
- Keep DeveloperID/self-hosted behavior independently releasable until Apple
  hosting has proven stable in production.

## Completion checklist

- [x] Confirm app version 3.2.4.
- [x] Set build number 371 across app and extension configurations.
- [x] Freeze the three permanent asset-pack IDs.
- [x] Resolve packaged CLIP, SAM, and Qwen provenance discrepancies.
- [x] Evaluate all file selectors and compare the selected inventory.
- [x] Regenerate all three archives with release Xcode.
- [x] Record final hashes, sizes, tooling, model fingerprints, and licences.
- [x] Upload CLIP version 1 and verify `COMPLETE` processing.
- [x] Upload SAM 3 version 1 and verify `COMPLETE` processing.
- [x] Upload Qwen version 1 and verify `COMPLETE` processing.
- [x] Confirm all three internal beta releases are Ready for Testing.
- [x] Add the AppStore build configuration and App Store export workflow.
- [x] Add the Apple-hosted Info.plist with only the three permitted keys.
- [x] Select `StoreDownloaderExtension` for AppStore builds.
- [x] Select `.appleHosted` in the AppStore application code.
- [x] Add Qwen to the managed-download enum, catalog, and production inclusion.
- [x] Route managed Qwen locations into `QwenInferenceRuntime`.
- [x] Implement explicit managed/custom Qwen source precedence.
- [x] Update AI Settings and the download sheet.
- [ ] Update the manifest template, provenance schema, notices, scripts, and
  docs. **Template, provenance records/schema, scripts, and model-assets docs
  are complete; remaining documentation/notice review is pending.**
- [ ] Update model-download, Qwen, release-metadata, UI, and accessibility
  tests. **Focused model-download and release-metadata coverage passes;
  additional UI/accessibility coverage remains.**
- [ ] Run provenance, smoke, focused, and archive-verification checks.
  **Provenance checks, focused tests, AppStore/Release builds, plist validation,
  and diff checks pass; full smoke and signed-archive verification remain.**
- [ ] Upload the AppStore build and complete clean-install internal TestFlight tests.
- [ ] Submit the app and all three tested pack versions together for review.
- [x] Retain the self-hosted path until the Apple-hosted production rollout is verified.
