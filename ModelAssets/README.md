# RawCull model asset packs

`manifest.template.json` is the developer-side Managed Background Assets
manifest skeleton for the two managed-download model bundles: DataComp CLIP and Meta SAM 3. It contains no
model files and is not served by the application.

`Notices` is the checked-in source for each pack's licence, attribution, and
provenance catalog. Copy the matching catalog into the release staging tree at
`Notices/<bundle-name>` before packaging. A catalog documents known evidence;
its presence does not override a release blocker in
`RawCullAIModelDownloadCatalog.production`.

## Audited 3.0.0 inputs

The template destinations and the application catalog agree exactly. Managed
Background Assets resolves these paths inside the downloaded asset pack;
manual installations use the corresponding directory below RawCull's
Application Support `Models` directory.

| Pack | Asset pack ID | Manifest/catalog destination | Recorded model evidence | Bundled acceptance-text SHA-256 | 3.0.0 distribution state |
|---|---|---|---|---|---|
| DataComp CLIP | `no.blogspot.RawCull.models.clip-datacomp` | `Models/CLIP-DataComp` | v3 archive: 282,966,632 bytes; SHA-256 `cf433dcd199b44635a4ff0260bd8e79177e4907a4cfcb2f72043066b8cbe4ef7`; reference revision `4afec35ffe57a943d569ff7ee888061830164da8` | `6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986` | Published in the `v3` model release |
| Meta SAM 3 | `no.blogspot.RawCull.models.sam3` | `Models/SAM3` | runtime MLIRB `43a9b88e40d193f5a6608a7fee536a78f4ba4ec5d95f1eb24db03031630f0a31`; local snapshot `3c879f39826c281e95690f02c7821c4de09afae7` | `b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab` | Published in the `v3` model release; archive: 1,542,689,157 bytes; SHA-256 `dd0adc697060129435d4a70515011a37f547e1ad7cd530d943341bf3ca9184a9` |

DataComp records its published v3 archive. OpenAI CLIP and EfficientSAM retain
prepared metadata and notices for reference, but are excluded from the download
sheet and manifest template. SAM 3 is ready for download, with its v3 archive metadata verified against
GitHub and the published manifest on September 6, 2026.
No model binary or generated asset-pack archive is checked into this repository.

Before publishing a pack:

1. Resolve the corresponding release blocker in
   `RawCullAIModelDownloadCatalog.production`.
2. Put the converted bundle, complete applicable licence text, provenance,
   conversion metadata, and checksums under the selector's source directory.
3. Generate the deployable manifest and archives with the Managed Background
   Assets tools in the release version of Xcode.
4. Upload the archives first and the generated manifest last.
5. Update RawCull's `BAManifestURL` only after verifying the production files
   over HTTPS.

The checked-in app configuration uses
`https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/manifest.json`,
sets `BAUsesAppleHosting` to `NO`, and shares
`group.no.blogspot.RawCull.model-assets` between the sandboxed app and
downloader extension. The developer template and app download sheet contain only
DataComp CLIP and Meta SAM 3. The published v3 manifest contains these same two packs.

For Apple hosting, upload the same packs in App Store Connect, set
`BAUsesAppleHosting` to `YES`, remove `BAManifestURL`, and compile the extension
with `RAWCULL_APPLE_HOSTED_MODEL_ASSETS`.

## Production provenance validation

SAM 3 selection, loading, and downloads are enabled. RawCull requires explicit acceptance of its verified bundled licence before downloading. The provenance record documents the project owner’s release decision and verified archive metadata.

Run `make verify-model-provenance` to validate all production-enabled models against their notice/provenance records. `release-preflight` runs the same check. It rejects blocked or missing evidence, malformed records, archive hash/size mismatches, model identity/revision mismatches, and invalid notice hashes. `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/TestModelProvenance.py` exercises rejection cases using temporary repository fixtures.

The CLIP provenance records now include the archive hashes and sizes already documented in the table above; this change does not represent a new download or redistribution review.
