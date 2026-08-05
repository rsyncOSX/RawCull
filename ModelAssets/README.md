# RawCull model asset packs

`manifest.template.json` is the developer-side Managed Background Assets
manifest skeleton for the four optional model bundles. It contains no model
files and is not served by the application.

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
| DataComp CLIP | `no.blogspot.RawCull.models.clip-datacomp` | `Models/CLIP-DataComp` | runtime MLIRB `70b6a8b3502626dbfd4e228dff1e060e06606c93e7a19c8f260dba95b9a7d01e`; reference revision `4afec35ffe57a943d569ff7ee888061830164da8` | `6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986` | Blocked: exporter did not cryptographically bind exact source weights |
| OpenAI CLIP | `no.blogspot.RawCull.models.clip-openai` | `Models/CLIP-OpenAI` | runtime MLIRB `34b1c3f2eccfac50e5c47eeb33029b8c488fb7f3712d50d6d46965625a6a3798`; local snapshot `3d74acf9a28c67741b2f4f2ea7635f0aaf6f0268` | `893951b3bf94db8df1b13e05da5cdeb499400960e4d44a3962a8b33ed0b4f28e` | Blocked: exact weights still need immutable revision and licence verification |
| EfficientSAM | `no.blogspot.RawCull.models.efficient-sam` | `Models/EfficientSAM` | Not recorded; compile the 8×8 segment-everything bundle and fingerprint it before staging | Not applicable | Blocked: source revision, checkpoint checksum, converted fingerprint, archive checksum, and notices are not recorded |
| Meta SAM 3 | `no.blogspot.RawCull.models.sam3` | `Models/SAM3` | runtime MLIRB `43a9b88e40d193f5a6608a7fee536a78f4ba4ec5d95f1eb24db03031630f0a31`; local snapshot `3c879f39826c281e95690f02c7821c4de09afae7` | `b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab` | Blocked: ungated redistribution has not been cleared against the SAM License and gated access terms |

These hashes describe checked-in evidence, not a downloadable archive. All
four production descriptors intentionally have no archive checksum, download
size, or installed size while distribution is blocked. No model binary or
generated asset-pack archive is checked into this repository. Consequently,
the recorded runtime hashes are provenance references and do not claim that a
release model was exercised by the repository-only test run.

Before publishing a pack:

1. Resolve the corresponding release blocker in
   `RawCullAIModelDownloadCatalog.production`.
2. Put the converted bundle, complete applicable licence text, provenance,
   conversion metadata, and checksums under the selector's source directory.
3. Generate the deployable manifest and archives with the Managed Background
   Assets tools in the release version of Xcode.
4. Upload the archives first and the generated manifest last.
5. Replace RawCull's `.invalid` `BAManifestURL` only after verifying the
   production files over HTTPS.

The checked-in app configuration deliberately uses
`https://example.invalid/rawcull/models/manifest.json`, sets
`BAUsesAppleHosting` to `NO`, and shares
`group.no.blogspot.RawCull.model-assets` between the sandboxed app and
downloader extension. This is a release-safe disabled state, not a production
download endpoint.

For Apple hosting, upload the same packs in App Store Connect, set
`BAUsesAppleHosting` to `YES`, remove `BAManifestURL`, and compile the extension
with `RAWCULL_APPLE_HOSTED_MODEL_ASSETS`.
