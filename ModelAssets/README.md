# RawCull model asset packs

`manifest.template.json` is the developer-side Managed Background Assets
manifest skeleton for the four managed-download model bundles. It contains no
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
| DataComp CLIP | `no.blogspot.RawCull.models.clip-datacomp` | `Models/CLIP-DataComp` | v2 archive: 282,966,632 bytes; SHA-256 `cf433dcd199b44635a4ff0260bd8e79177e4907a4cfcb2f72043066b8cbe4ef7`; reference revision `4afec35ffe57a943d569ff7ee888061830164da8` | `6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986` | Published in the `v2` model release |
| OpenAI CLIP | `no.blogspot.RawCull.models.clip-openai` | `Models/CLIP-OpenAI` | v2 archive: 282,866,068 bytes; SHA-256 `e9181157c2d4012db2e6478949488f9906696a4ed78ecaa10235d9762621136c`; source revision `3d74acf9a28c67741b2f4f2ea7635f0aaf6f0268`; source weight SHA-256 `a63082132ba4f97a80bea76823f544493bffa8082296d62d71581a4feff1576f` | `893951b3bf94db8df1b13e05da5cdeb499400960e4d44a3962a8b33ed0b4f28e` | Published in the `v2` model release |
| EfficientSAM | `no.blogspot.RawCull.models.efficient-sam` | `Models/EfficientSAM` | source revision `d525f622e6f640acf5a0fc37c7ca1f243da5bde0`; checkpoint revision `38bb0b55425abf62274ba4a8c51249e3d7298b70`; checkpoint: 40,982,470 bytes; SHA-256 `dff858b19600a46461cbb7de98f796b23a7a888d9f5e34c0b033f7d6eb9e4e6a` | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` | Prepared and blocked pending final converted-bundle fingerprint and generated archive evidence |
| Meta SAM 3 | `no.blogspot.RawCull.models.sam3` | `Models/SAM3` | runtime MLIRB `43a9b88e40d193f5a6608a7fee536a78f4ba4ec5d95f1eb24db03031630f0a31`; local snapshot `3c879f39826c281e95690f02c7821c4de09afae7` | `b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab` | Blocked: ungated redistribution review and final generated archive evidence remain open |

The CLIP entries record their published v2 archives. EfficientSAM and SAM 3
remain blocked; their hashes describe preparation evidence rather than a
downloadable archive. EfficientSAM's exact export command and unfilled final-
artifact evidence fields are recorded in its provenance catalog. SAM 3 still
requires a redistribution decision for its gated source and custom licence.
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
`https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v2/manifest.json`,
sets `BAUsesAppleHosting` to `NO`, and shares
`group.no.blogspot.RawCull.model-assets` between the sandboxed app and
downloader extension. The production manifest currently publishes the
on-demand DataComp and OpenAI CLIP packs. The developer template also prepares
EfficientSAM and SAM 3 selectors, but descriptors that remain release-blocked
are not included in the deployable manifest and are not downloadable.

For Apple hosting, upload the same packs in App Store Connect, set
`BAUsesAppleHosting` to `YES`, remove `BAManifestURL`, and compile the extension
with `RAWCULL_APPLE_HOSTED_MODEL_ASSETS`.
