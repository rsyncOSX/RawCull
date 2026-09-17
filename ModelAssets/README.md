# RawCull model asset packs

`manifest.template.json` is the developer-side Managed Background Assets
manifest skeleton for the three managed-download model bundles: DataComp CLIP,
Meta SAM 3, and Qwen3-VL-2B-Instruct. It contains no
model files and is not served by the application.

`Notices` is the checked-in source for each pack's licence, attribution, and
provenance catalog. Copy the matching catalog into the release staging tree at
`Notices/<bundle-name>` before packaging. A catalog documents known evidence;
its presence does not override a release blocker in
`RawCullAIModelDownloadCatalog.production`.

## Audited Apple-hosted inputs

The template destinations and the application catalog agree exactly. Managed
Background Assets resolves these paths inside the downloaded asset pack;
manual installations use the corresponding directory below RawCull's
Application Support `Models` directory.

| Pack | Asset pack ID | Manifest/catalog destination | Apple-hosted archive evidence | Bundled acceptance-text SHA-256 | Distribution state |
|---|---|---|---|---|---|
| DataComp CLIP | `rawcull-clip-datacomp` | `Models/CLIP-DataComp` | 282,967,354 bytes; SHA-256 `994939e74dbbe9844214d509267642939f5ddc535ae3bce4be36c8855bdfa600`; reference revision `4afec35ffe57a943d569ff7ee888061830164da8` | `6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986` | Apple-hosted version 1 processed successfully; review pending |
| Meta SAM 3 | `rawcull-sam3` | `Models/SAM3` | 1,542,689,931 bytes; SHA-256 `08c9a4f58242d6eecaa322d65521fd788589ea682aa92a5cea03fa1e2f2681d4`; revision `3c879f39826c281e95690f02c7821c4de09afae7` | `b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab` | Apple-hosted version 1 processed successfully; review pending |
| Qwen3-VL-2B-Instruct | `rawcull-qwen3-vl-2b` | `Models/Qwen/qwen3_vl_2b` | 3,754,599,603 bytes; SHA-256 `115eebbfdff7cb688b26dd6e2dd6c110b3fce5d27f6d5e8f40f69192d1ca2364`; revision `78448d793a7eb2f7a987a1da76d464384aa1becd` | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` | Apple-hosted version 1 processed successfully; review pending |

OpenAI CLIP and EfficientSAM retain prepared metadata and notices for reference,
but are excluded from the download sheet and manifest template. The three
production archives were generated and hashed on September 17, 2026.
No model binary or generated asset-pack archive is checked into this repository.

Before publishing a pack:

1. Resolve the corresponding release blocker in
   `RawCullAIModelDownloadCatalog.production`.
2. Put the converted bundle, complete applicable licence text, provenance,
   conversion metadata, and checksums under the selector's source directory.
3. Generate the deployable manifest and archives with the Managed Background
   Assets tools in the release version of Xcode.
4. Upload each archive to RawCull's App Store Connect record and wait for Apple
   processing to succeed before selecting it for a beta or App Store release.
5. Record the Apple-assigned pack version, processing result, and review state
   in the external release evidence.

The Direct/Developer ID configuration continues to use
`https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/manifest.json`,
sets `BAUsesAppleHosting` to `NO`, and shares
`group.no.blogspot.RawCull.model-assets` between the sandboxed app and
downloader extension.

The dedicated `AppStore` configuration uses `RawCull-AppStore-Info.plist`, sets
`BAUsesAppleHosting` to `YES`, omits `BAManifestURL` and all self-hosted
restrictions, and compiles the app and extension with
`RAWCULL_APPLE_HOSTED_MODEL_ASSETS`. Build it with `make archive-app-store`.

## Production provenance validation

DataComp CLIP, SAM 3, and Qwen downloads are enabled for the Apple-hosted build.
RawCull requires explicit acceptance of SAM 3's verified bundled licence before
downloading. The provenance records document the project owner's packaging
decision and verified local archive metadata; they do not claim that Apple has
processed or approved a pack unless its provenance includes the corresponding
App Store Connect record, version, processing, and internal-beta evidence.

Run `make verify-model-provenance` to validate all production-enabled models against their notice/provenance records. `release-preflight` runs the same check. It rejects blocked or missing evidence, malformed records, archive hash/size mismatches, model identity/revision mismatches, and invalid notice hashes. `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/TestModelProvenance.py` exercises rejection cases using temporary repository fixtures.

The Apple-hosted provenance records include the archive hashes and sizes in the
table above. All three version 1 packs have completed App Store Connect
processing and their internal beta releases are ready for testing. App Review
remains an external release step and must not be inferred from these records.
