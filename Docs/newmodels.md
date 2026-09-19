# Adding or updating Apple-hosted RawCull model packs

This runbook describes the complete RawCull workflow for turning converted
model files into an Apple-hosted Managed Background Assets archive (`.aar`),
updating the application metadata, uploading the archive with `xcrun altool`,
and verifying both Apple processing and an actual TestFlight download.

The examples use these RawCull values:

```text
App name:          RawCull
Bundle ID:         no.blogspot.RawCull
Apple ID:          6759362764
Platform:          macOS
Download policy:   onDemand
Source root:       /Users/thomas/ModelAssets/Release
Repository root:   /Users/thomas/GitHub/RawCull/RawCull
```

Never commit model binaries, generated `.aar` files, App Store Connect API
private keys, JSON Web Tokens, or passwords to this repository.

## 1. Decide whether this is a new pack or a new version

Use the same asset-pack ID when only the contents of an existing model pack
change. Apple will assign the upload a new monotonically increasing pack
version.

Create a new asset-pack ID only when adding a genuinely separate pack. An ID is
permanent once it is used in App Store Connect. Archiving a pack removes all of
its versions and does not make its ID reusable.

RawCull IDs must follow Apple's accepted syntax:

- use only `A-Z`, `a-z`, `0-9`, and `-`;
- do not use dots, underscores, spaces, or slashes; and
- do not begin or end the ID with `-`.

Use the RawCull convention `rawcull-<short-model-name>`, for example
`rawcull-sam3`. The ID in the packaging manifest, repository manifest, Swift
catalog, provenance record, and App Store Connect must be identical.

Before doing any work, choose and record:

```text
MODEL_SLUG=<short filename-safe name>
ASSET_PACK_ID=rawcull-<short-model-name>
RESOURCE_NAME=<notice/provenance directory name>
MODEL_DESTINATION=Models/<installed relative path>
ARCHIVE_NAME=<model-slug>.aar
```

For the shell examples, set task-specific variables with the real values. This
example deliberately uses a fictitious model:

```bash
RAWCULL_RELEASE_ROOT='/Users/thomas/ModelAssets/Release'
RAWCULL_MODEL_SLUG='example-model'
RAWCULL_ASSET_PACK_ID='rawcull-example-model'
RAWCULL_RESOURCE_NAME='Example'
RAWCULL_MODEL_SOURCE='Models/Example'
RAWCULL_MODEL_DESTINATION='Models/Example'
RAWCULL_ARCHIVE_NAME='example-model.aar'
```

## 2. Prepare and freeze the source tree

Place the converted model and its supporting files below:

```text
/Users/thomas/ModelAssets/Release/Models/<model path>/
```

Create or update the corresponding release evidence below:

```text
/Users/thomas/ModelAssets/Release/Notices/<RESOURCE_NAME>/NOTICE.md
/Users/thomas/ModelAssets/Release/Notices/<RESOURCE_NAME>/PROVENANCE.json
/Users/thomas/ModelAssets/Release/Notices/<RESOURCE_NAME>/<licence files>.txt
```

The notice directory must contain every licence and attribution required by the
model, tokenizer, conversion code, and other redistributed components. Pin
upstream source revisions and record source/model-tree checksums before
packaging. Confirm that redistribution is allowed; Apple hosting does not
remove licence obligations.

Inspect the selected tree for unwanted files and symbolic links:

```bash
cd "$RAWCULL_RELEASE_ROOT"

find "$RAWCULL_MODEL_SOURCE" "Notices/$RAWCULL_RESOURCE_NAME" \
  \( -name '.DS_Store' -o -type l \) -print
```

Resolve every result before continuing. Freeze the input tree once verified.
If any selected byte changes later, regenerate and remeasure the `.aar`.

It is useful to retain a sorted input inventory outside the model directories:

```bash
cd "$RAWCULL_RELEASE_ROOT"
mkdir -p Evidence

find "$RAWCULL_MODEL_SOURCE" "Notices/$RAWCULL_RESOURCE_NAME" -type f -print0 \
  | xargs -0 shasum -a 256 \
  | sort \
  > "Evidence/$RAWCULL_MODEL_SLUG-input-sha256.txt"
```

Do not include the final archive's own checksum inside the archive's embedded
provenance file. That would create a self-referential checksum. Add the final
archive hash to the repository provenance record after packaging.

## 3. Create the packaging manifest

Create this file:

```text
/Users/thomas/ModelAssets/Release/Packaging/<model-slug>.json
```

Start from this shape and list only the files and directories that belong in
the pack:

```json
{
  "assetPackID": "rawcull-example-model",
  "downloadPolicy": {
    "onDemand": {}
  },
  "fileSelectors": [
    { "file": "Models/Example/metadata.json" },
    { "directory": "Models/Example/tokenizer" },
    { "directory": "Models/Example/example.aimodel" },
    { "directory": "Notices/Example" }
  ],
  "platforms": [
    "macOS"
  ]
}
```

The paths are resolved from the current working directory, so run
`ba-package` from `/Users/thomas/ModelAssets/Release`. For RawCull model packs,
the manifest must contain exactly:

```json
"platforms": ["macOS"]
```

and:

```json
"downloadPolicy": {"onDemand": {}}
```

Do not use `essential` or `prefetch` for these multi-gigabyte optional models.

## 4. Evaluate the manifest before packaging

Use the release Xcode selected by `xcode-select`, then record its versions:

```bash
xcodebuild -version
xcrun ba-package --version
```

Evaluate the selectors:

```bash
cd "$RAWCULL_RELEASE_ROOT"
xcrun ba-package evaluate "Packaging/$RAWCULL_MODEL_SLUG.json" \
  | tee "Evidence/$RAWCULL_MODEL_SLUG-evaluate.txt"
```

Compare every path printed by `evaluate` with the frozen inventory. The list
must contain only the intended model bundles, tokenizer/configuration files,
metadata, notices, licences, and provenance. It must not contain `.DS_Store`,
temporary output, a previous `.aar`, secrets, or unrelated models.

Do not package until `evaluate` succeeds and its list is understood.

## 5. Generate the `.aar`

Create the archive from the same frozen source tree:

```bash
cd "$RAWCULL_RELEASE_ROOT"

xcrun ba-package package "Packaging/$RAWCULL_MODEL_SLUG.json" \
  --output-path "Output/$RAWCULL_ARCHIVE_NAME" \
  --verbose
```

`ba-package` archives are not ordinary ZIP files. Do not use `zip`, `unzip`,
or another archiver to create or modify them. If the contents need to change,
change the frozen inputs and run `ba-package package` again.

## 6. Verify the generated archive

First rerun evaluation to ensure the selectors still resolve to the frozen
inventory:

```bash
cd "$RAWCULL_RELEASE_ROOT"
xcrun ba-package evaluate "Packaging/$RAWCULL_MODEL_SLUG.json"
```

Record the exact logical size and SHA-256:

```bash
stat -f '%N|%z' "Output/$RAWCULL_ARCHIVE_NAME"
shasum -a 256 "Output/$RAWCULL_ARCHIVE_NAME"
shasum -a 256 "Packaging/$RAWCULL_MODEL_SLUG.json"
```

Create a release-evidence row containing at least:

| Field | Required value |
|---|---|
| Asset-pack ID | Exact permanent ID |
| Archive filename | Exact `.aar` filename |
| Archive byte count | Output from `stat` |
| Archive SHA-256 | Output from `shasum -a 256` |
| Packaging-manifest SHA-256 | Output from `shasum -a 256` |
| Xcode and `ba-package` versions | Recorded command output |
| Selected file inventory | Reviewed `evaluate` output |
| Model-tree fingerprint | Frozen input evidence |
| Upstream revision/checksums | Immutable upstream evidence |
| Licence/notice checksums | Every redistributed notice |
| Packaging date | ISO date or unambiguous written date |

The archive ID itself is embedded by `ba-package`. A successful evaluation,
the reviewed manifest, and the upload result together establish which ID and
platform were packaged.

## 7. Update RawCull before enabling the model

### 7.1 Repository manifest

Add or update the entry in:

```text
ModelAssets/manifest.template.json
```

The entry's `assetPackID`, `downloadPolicy`, destination, and platform must
match the packaging manifest. The destination is the path RawCull receives
inside the installed asset pack.

### 7.2 Notices and provenance

Add or update:

```text
ModelAssets/Notices/<RESOURCE_NAME>/NOTICE.md
ModelAssets/Notices/<RESOURCE_NAME>/PROVENANCE.json
ModelAssets/Notices/<RESOURCE_NAME>/<licence files>.txt
ModelAssets/README.md
```

Before upload, the repository provenance should contain the final archive
hash/size and normally use:

```json
{
  "hosting": "apple",
  "app_bundle_id": "no.blogspot.RawCull",
  "asset_pack_id": "rawcull-example-model",
  "archive_sha256": "<64 lowercase hexadecimal characters>",
  "archive_byte_count": 123456789,
  "packaging_date": "YYYY-MM-DD",
  "processing_status": "pending-upload",
  "review_state": "not-submitted"
}
```

After Apple processes the upload, add the record ID, Apple-assigned version,
version ID, processing date, internal-beta release ID/state, and change
`processing_status` to `succeeded`. Do not mark App Review approved unless
App Store Connect actually reports approval.

### 7.3 Swift catalog and inclusion switches

Update:

```text
RawCull/Intelligence/ModelManagement/RawCullAIModelDownloadCatalog.swift
```

For a new model:

1. Add a stable case to `RawCullAIModelDownloadID`.
2. Add the appropriate code-only inclusion/download flag.
3. Map the flag in `downloadIDs` and, when relevant, the CLIP or segmentation
   selection list.
4. Add a `RawCullAIModelDownloadDescriptor` to `prepared`.
5. Set `assetPackID` and `assetPackModelPath` exactly as recorded in the two
   manifests.
6. Set `expectedArchiveSHA256` and `downloadByteCount` from the final `.aar`.
7. Record the installed byte count, upstream revision, URLs, licence metadata,
   and bundled licence checksum.
8. Keep `releaseReadiness` blocked until all required evidence is complete;
   change it to `.ready` only when the pack is releasable.

For a new version of an existing pack, retain its permanent ID and normally
update only the descriptor's model revision, archive hash, archive byte count,
installed byte count, licence/provenance information, and any model path that
actually changed.

A new model family may also require runtime integration beyond the download
catalog. Search for the nearest existing model implementation and update the
corresponding contracts, paths, provider composition, Settings model/UI, and
tests. Merely making a pack downloadable does not make RawCull able to use its
model format.

### 7.4 Tests with explicit model lists

At minimum inspect and update:

```text
RawCullTests/RawCullAIModelDownloadsTests.swift
RawCullTests/ReleaseMetadataTests.swift
Scripts/TestModelProvenance.py
```

`RawCullAIModelDownloadsTests` has explicit production model and evidence
expectations. `ReleaseMetadataTests` has an explicit asset-pack ID to installed
destination mapping. `TestModelProvenance.py` checks the enabled model list.

Use `rg` to find any additional hard-coded model identifiers:

```bash
cd /Users/thomas/GitHub/RawCull/RawCull
rg -n '<swift-case>|<model-slug>|<asset-pack-id>|<RESOURCE_NAME>' \
  RawCull RawCullTests ModelAssets Scripts
```

## 8. Run repository verification before upload

Run the provenance checks:

```bash
cd /Users/thomas/GitHub/RawCull/RawCull

PYTHONDONTWRITEBYTECODE=1 python3 Scripts/VerifyModelProvenance.py
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/TestModelProvenance.py
```

Run the focused catalog and release-metadata tests:

```bash
xcodebuild test \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile \
  -only-testing:RawCullTests/RawCullAIModelDownloadsTests \
  -only-testing:RawCullTests/ReleaseMetadataTests
```

Then run the normal release checks appropriate to the change:

```bash
make verify-ai-import-boundary
make test-smoke
git diff --check
```

Do not upload if the packaging manifest, repository manifest, Swift catalog,
provenance record, and tests disagree on the pack ID or destination.

## 9. Configure and protect the App Store Connect `.p8` key

Create a Team API key in App Store Connect under:

```text
Users and Access > Integrations > App Store Connect API > Team Keys
```

Record its **Key ID** and the page's **Issuer ID**, then download the private
key. Apple lets you download the `.p8` private key only once.

The following values are different and must not be confused:

- **RawCull Apple ID:** the numeric application ID `6759362764`;
- **Key ID:** identifies the API key;
- **Issuer ID:** identifies the App Store Connect API issuer/team; and
- **`.p8` file:** the secret private key used to sign authentication tokens.

Protect the downloaded file:

```bash
chmod 600 /secure/path/AuthKey_<KEY_ID>.p8
```

Do not paste its contents into Terminal, documentation, source code, an
environment variable, a chat, or a Git commit. Keep a protected backup in the
team's approved secret/password manager.

For the commands below, define only non-secret identifiers and the private
key's path in the current shell:

```bash
RAWCULL_APPLE_ID='6759362764'
RAWCULL_ASC_KEY_ID='<KEY_ID>'
RAWCULL_ASC_ISSUER_ID='<ISSUER_ID>'
RAWCULL_ASC_P8='/secure/path/AuthKey_<KEY_ID>.p8'
```

Confirm the file exists without printing it:

```bash
test -f "$RAWCULL_ASC_P8" && test -r "$RAWCULL_ASC_P8"
```

`altool` accepts the key directly with `--p8-file-path`; this is the clearest
option and avoids copying the key. Alternatively, name it
`AuthKey_<KEY_ID>.p8` and place it in one of altool's protected search
directories, preferably:

```text
~/.appstoreconnect/private_keys/
```

When using that search directory, omit `--p8-file-path`. In both cases provide
`--api-key` and `--api-issuer`. The private-key contents remain secret; the Key
ID and Issuer ID are identifiers rather than the signing secret.

Test authentication by listing RawCull's packs:

```bash
xcrun altool \
  --list-asset-packs \
  --apple-id "$RAWCULL_APPLE_ID" \
  --api-key "$RAWCULL_ASC_KEY_ID" \
  --api-issuer "$RAWCULL_ASC_ISSUER_ID" \
  --p8-file-path "$RAWCULL_ASC_P8" \
  --output-format json
```

A `401 NOT_AUTHORIZED` response means the key, issuer, token/signature, key
path, or permission is wrong. It does not mean the numeric Apple ID is wrong.
The API key needs a role permitted to upload asset packs.

## 10. Ensure a permanent App Store Connect pack record exists

List the records before uploading:

```bash
xcrun altool \
  --list-asset-packs \
  --apple-id "$RAWCULL_APPLE_ID" \
  --api-key "$RAWCULL_ASC_KEY_ID" \
  --api-issuer "$RAWCULL_ASC_ISSUER_ID" \
  --p8-file-path "$RAWCULL_ASC_P8" \
  --output-format json
```

For an existing pack, confirm the exact permanent ID is present and reuse it.
Do not create a second ID for an ordinary model update.

For a genuinely new ID, create one asset-pack record associated with RawCull.
The explicit App Store Connect API request uses:

```text
POST https://api.appstoreconnect.apple.com/v1/backgroundAssets
```

with this body:

```json
{
  "data": {
    "type": "backgroundAssets",
    "attributes": {
      "assetPackIdentifier": "rawcull-example-model"
    },
    "relationships": {
      "app": {
        "data": {
          "type": "apps",
          "id": "6759362764"
        }
      }
    }
  }
}
```

Authenticate the API request with a short-lived bearer token signed by the
`.p8` key. `xcrun altool --generate-jwt --api-key <KEY_ID> --api-issuer
<ISSUER_ID> --p8-file-path <path>` can generate a token for an API client.
Never save or commit that token. Record the UUID returned by the successful
`201 Created` response in the model's external release evidence. If the record
already exists, use it; do not retry creation with a different spelling.

## 11. Upload the `.aar` with `xcrun altool`

Upload the smallest new pack first when validating a new workflow. Use
`--wait` so altool waits for a ready or failed processing result:

```bash
xcrun altool \
  --upload-asset-pack "$RAWCULL_RELEASE_ROOT/Output/$RAWCULL_ARCHIVE_NAME" \
  --apple-id "$RAWCULL_APPLE_ID" \
  --api-key "$RAWCULL_ASC_KEY_ID" \
  --api-issuer "$RAWCULL_ASC_ISSUER_ID" \
  --p8-file-path "$RAWCULL_ASC_P8" \
  --wait \
  --show-progress \
  --output-format json
```

Save the non-secret result as release evidence. Record:

- asset-pack record ID;
- Apple-assigned version number;
- asset-pack version UUID;
- delivery/upload result;
- processing state and state details;
- platform reported by Apple; and
- internal-beta release ID and state when created.

Never edit an archive after uploading it. If content or evidence is wrong,
correct the frozen inputs, generate a new `.aar`, record its new hash and size,
and upload it as the next version under the same permanent ID.

## 12. Verify Apple processing from the command line

List the pack's versions:

```bash
xcrun altool \
  --list-asset-pack-versions \
  --apple-id "$RAWCULL_APPLE_ID" \
  --asset-pack-identifier "$RAWCULL_ASSET_PACK_ID" \
  --api-key "$RAWCULL_ASC_KEY_ID" \
  --api-issuer "$RAWCULL_ASC_ISSUER_ID" \
  --p8-file-path "$RAWCULL_ASC_P8" \
  --output-format json
```

Check a particular Apple-assigned version and wait if it is still processing:

```bash
RAWCULL_ASSET_PACK_VERSION='<apple-assigned-version>'

xcrun altool \
  --asset-pack-status \
  --apple-id "$RAWCULL_APPLE_ID" \
  --asset-pack-identifier "$RAWCULL_ASSET_PACK_ID" \
  --version "$RAWCULL_ASSET_PACK_VERSION" \
  --api-key "$RAWCULL_ASC_KEY_ID" \
  --api-issuer "$RAWCULL_ASC_ISSUER_ID" \
  --p8-file-path "$RAWCULL_ASC_P8" \
  --wait \
  --output-format json
```

The upload is ready for internal testing only after all of these are true:

- the exact asset-pack ID belongs to RawCull;
- the version state is successful (`COMPLETE` in App Store Connect API output,
  rather than processing or failed);
- the version reports `MAC_OS`/macOS only;
- there are no validation errors or unexpected warnings;
- the reported file/used size is plausible for the local `.aar`; and
- the Internal Beta Release is `READY_FOR_TESTING`.

`altool` can report archive processing, but use App Store Connect or the
Background Assets API when the altool response does not include the internal
beta relationship/state. Apple's version endpoint is:

```text
GET https://api.appstoreconnect.apple.com/v1/backgroundAssets/<record-id>/versions
```

Request the version's `state`, `platforms`, `version`, and
`internalBetaRelease` relationship. A completed archive without a
`READY_FOR_TESTING` internal beta release is not yet fully ready for the next
step.

## 13. Update provenance after successful processing

Update the repository `PROVENANCE.json` release object with the values returned
by Apple:

```json
{
  "hosting": "apple",
  "app_bundle_id": "no.blogspot.RawCull",
  "asset_pack_id": "rawcull-example-model",
  "asset_pack_record_id": "<record UUID>",
  "asset_pack_version": "<Apple version>",
  "asset_pack_version_id": "<version UUID>",
  "archive_sha256": "<local archive SHA-256>",
  "archive_byte_count": 123456789,
  "packaging_date": "YYYY-MM-DD",
  "processing_status": "succeeded",
  "processing_date": "YYYY-MM-DD",
  "internal_beta_release_id": "<internal beta UUID>",
  "internal_beta_state": "ready-for-testing",
  "review_state": "not-submitted"
}
```

Update `ModelAssets/README.md` and the release evidence document, then rerun:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/VerifyModelProvenance.py
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/TestModelProvenance.py

xcodebuild test \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS' \
  -onlyUsePackageVersionsFromResolvedFile \
  -only-testing:RawCullTests/RawCullAIModelDownloadsTests \
  -only-testing:RawCullTests/ReleaseMetadataTests

git diff --check
```

## 14. Verify an actual TestFlight download

Successful archive processing proves Apple accepted the pack; it does not prove
that the signed RawCull build requests and uses it correctly.

1. Build and upload RawCull with the `AppStore` configuration. Both the app and
   `RawCullModelDownloader` extension must use the same App Group and App Store
   signing team.
2. Confirm the built app uses `RawCull-AppStore-Info.plist`, with
   `BAUsesAppleHosting = YES`, `BAHasManagedAssetPacks = YES`, and
   `BAAppGroupID = group.no.blogspot.RawCull.model-assets`.
3. Confirm the self-hosted `BAManifestURL` and download restrictions are absent
   from the App Store build.
4. Wait until the RawCull TestFlight build and the pack's Internal Beta Release
   are both ready for testing.
5. Install the build through TestFlight on a clean macOS test account or remove
   any previously installed copy and managed model data first.
6. Open RawCull's model management UI and request the new model.
7. Confirm the displayed ID/model is the intended pack, progress advances, the
   operation completes without `assetPackNotFound`, authentication, manifest,
   or Background Assets errors, and RawCull reports the model installed.
8. Exercise the model's real feature. A completed download is not sufficient if
   the runtime cannot load its metadata, tokenizer, or `.aimodel` bundles.
9. Quit and relaunch RawCull. Confirm the installed model is rediscovered and
   remains usable.
10. Remove the model through RawCull, confirm its managed state changes, then
    download it again to verify a clean reinstall.
11. Save relevant App Store Connect status, TestFlight build number, test date,
    macOS version, RawCull logs, and observed results as release evidence.

For a new model family, also verify fallback behavior when the pack is absent,
download cancellation, licence acceptance when required, disk-space errors,
and switching between managed and user-selected model locations where the UI
supports both.

## 15. App Review and release

An Internal Beta Release in `READY_FOR_TESTING` is available only for internal
TestFlight testing. It is not automatically available to external testers or
App Store customers.

After successful internal testing:

1. submit the required pack version for external TestFlight beta review if
   external testing is needed;
2. create the App Store review submission containing the intended RawCull build
   and asset-pack versions;
3. verify each submitted pack's review state; and
4. change repository `review_state` only when App Store Connect supplies the
   corresponding evidence.

## 16. Common failures

### `Found invalid values` for `filter[assetPackIdentifier]`

The asset-pack ID contains a forbidden character, commonly a dot. Replace it
with a permanent ID using only letters, digits, and hyphens, then update the
packaging manifest, repository manifest, Swift catalog, tests, and provenance
before regenerating the `.aar`.

### `401 NOT_AUTHORIZED`

Check the `.p8` path, Key ID, Issuer ID, API-key role, and whether the key was
revoked. Do not substitute RawCull's numeric Apple ID for the Issuer ID.

### Pack is `COMPLETE`, but RawCull cannot find it

Check that:

- the TestFlight build uses the AppStore configuration and Apple-hosted plist;
- the downloader extension is embedded and correctly signed;
- its App Group matches the app;
- the Swift `assetPackID` exactly matches App Store Connect, including case;
- the Internal Beta Release is `READY_FOR_TESTING`; and
- the installed build came from TestFlight rather than the Developer ID/DMG
  workflow.

### Archive hash changed

Treat it as a different artifact. Re-run evaluation, record the new byte count
and SHA-256, update the catalog/provenance/tests, and upload it as a new pack
version. Never overwrite release evidence with values from an unexplained
artifact.

## Apple references

- [Creating managed asset packs](https://developer.apple.com/documentation/backgroundassets/creating-managed-asset-packs)
- [Upload Apple-hosted asset packs](https://developer.apple.com/help/app-store-connect/manage-asset-packs/upload-apple-hosted-asset-packs)
- [Background Assets API](https://developer.apple.com/documentation/appstoreconnectapi/background-assets)
- [Uploading and versioning Apple-hosted background assets](https://developer.apple.com/documentation/appstoreconnectapi/managing-apple-hosted-background-assets)
