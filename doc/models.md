# RawCullAI Core AI Model Distribution and Installation

## Purpose and scope

RawCullAI uses optional SAM 3 and CLIP models for subject detection and similarity scoring. On the `RawCullAI` branch these are **Core AI** models, not Core ML models. The runtime assets use the `.aimodel` format introduced with Core AI in Xcode 27 and macOS 27. PhotoAIKit also accepts architecture-specific `.aimodelc` assets produced by Core AI's ahead-of-time compiler.

The models are not currently included in the RawCullAI application bundle. RawCull owns their installation locations and user interface; the pinned PhotoAIKit dependency validates the installed resource directories and performs inference through `CoreAISAM3Backend` and `CoreAICLIPBackend`.

This document records the recommended product, technical, security, privacy, beta-release, and licensing approach for distributing and managing those resources.

Information and external terms were reviewed on July 15, 2026. Core AI, Xcode 27, macOS 27, and their documentation are currently beta and may change. Recheck all linked Apple documentation, release notes, service availability, and third-party model terms before every public release.

This is practical engineering and product guidance, not legal advice. The exact licence of every selected checkpoint and converted artifact must be reviewed before release.

## Correct terminology

The following distinctions are essential:

- **Core AI** is Apple's new framework for running modern neural-network models on Apple silicon. RawCullAI uses it for CLIP and SAM 3.
- **Core ML** is a different framework and uses formats such as `.mlpackage` and `.mlmodelc`. Those formats and `MLModel.compileModel(at:)` are not part of RawCullAI's current model path.
- **`.aimodel`** is Core AI's portable model asset. Core AI specializes it for the current device before inference.
- **`.aimodelc`** is an optional ahead-of-time-compiled Core AI asset produced by `coreai-build` for a particular Core AI device architecture. It still requires a smaller on-device specialization step.
- **Specialization** is Core AI's device- and OS-specific preparation step. It is not Core ML compilation and it does not normally create an application-managed `.mlmodelc` directory.
- **`AIModelCache`** stores specialized Core AI assets. Cached specializations are separate from RawCull's downloaded source bundle.
- **Model resource directory** in this document means a RawCull/PhotoAIKit directory containing `metadata.json`, tokenizer files, and the selected `.aimodel` or `.aimodelc`. It is an application packaging convention, not an Apple model-file extension.

Apple's [`AIModel`](https://developer.apple.com/documentation/coreai/aimodel) API loads either `.aimodel` or `.aimodelc`. Apple's [Core AI overview](https://developer.apple.com/documentation/coreai) explains when Core AI is appropriate and distinguishes it from Core ML.

## Current RawCullAI integration

The current source establishes these responsibilities:

- `RawCullAIPaths` owns the canonical Application Support locations.
- `RawCullAIModelResourceManager` supplies ordered candidate directories.
- PhotoAIKit's `ModelBundleResolver` validates the selected resource directory.
- `CoreAICLIPProvider` loads the selected asset with `AIModel(contentsOf:options:)` and uses its `main` inference function.
- `CoreAISAM3Provider` passes the selected Core AI asset to the Core AI segmentation engine.
- PhotoAIKit accepts selected assets ending in `.aimodel` or `.aimodelc`.
- PhotoAIKit does not embed or download model weights.
- RawCullAI's Settings controls and model-download flow are still incomplete. The documented Model Manager is a target design, not a claim that installation is already implemented.

Release builds search only the RawCull-owned installed directories. Debug builds may also use bundled fallback resources. The canonical installed locations are:

```text
~/Library/Application Support/RawCull/Models/SAM3/
~/Library/Application Support/RawCull/Models/CLIP/
```

In a sandboxed build, Foundation resolves the Application Support directory inside the application's container. Code must continue using Foundation URLs rather than constructing a literal home-directory path.

## Decision

Implement an **AI Model Manager inside RawCullAI**. Do not require ordinary users to install Python, PyTorch, `coreai-torch`, `coreai-optimization`, command-line tools, or a separate model-installer application.

The Model Manager should:

- Present each optional model and its purpose.
- Present the publisher, source, version, size, licence, model card, conversion details, and privacy information.
- Obtain explicit acceptance where required.
- Download a complete, versioned PhotoAIKit-compatible model resource archive.
- Verify and unpack the archive into a private temporary location.
- Validate `metadata.json`, the selected Core AI asset, tokenizer resources, and fingerprints.
- Optionally pre-specialize the selected asset with Core AI so the first feature use does not incur the full preparation delay.
- Atomically install the verified resource directory in RawCull's Application Support location.
- Enable the associated feature only after validation and, when used, successful specialization.
- Support updates, repair, removal, licence changes, and specialization-cache cleanup.

A standalone `RawCullAI Model Installer.app` should only be considered if several applications must share the same resources or the main application cannot perform downloads. A separate application adds signing, notarization, update, sandbox-sharing, App Group, and support complexity without changing the model-distribution licence obligations.

## Export, optimization, ahead-of-time compilation, and specialization

These are different operations and must not be described as one generic "compilation" step.

### 1. Export to Core AI

The RawCullAI developer or CI system starts from a pinned upstream PyTorch checkpoint. PhotoAIKit's export tools use Apple's Core AI PyTorch tooling to convert the exported PyTorch program into a `.aimodel` asset.

Apple describes converting models with `coreai-torch` and reducing their size with Core AI Optimization in its [Core AI technology overview](https://developer.apple.com/documentation/technologyoverviews/generative-models).

### 2. Optimize the portable model

The developer or CI system applies validated Core AI optimizations and saves the runtime `.aimodel`. Quantization and other changes must be recorded because they can affect size, speed, memory use, and output quality.

The PhotoAIKit exporters currently retain two developer artifacts:

- `*_source.aimodel`, the pre-optimization Core AI export; and
- `*.aimodel`, the optimized runtime asset selected by `metadata.json`.

The end-user archive does not need to contain both unless there is a documented operational reason. PhotoAIKit loads only the asset named by `metadata.json` under `assets.main`; shipping unused multi-gigabyte source artifacts wastes download and installed storage.

### 3. Optional ahead-of-time compilation

As an optional deployment optimization, the developer or CI system can run `coreai-build compile` on a `.aimodel`. Apple documents this in [Compiling Core AI models ahead of time](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time).

Ahead-of-time compilation produces a separate `.aimodelc` for each Core AI device architecture. RawCull should publish only the architecture variant required by the user's Mac and make `metadata.json` select that file. Query `AIModel.deviceArchitectureName` rather than assuming that every Apple-silicon Mac uses the same Core AI architecture identifier.

An `.aimodelc` is not a universal replacement for the `.aimodel`: it has a minimum OS version and a specific device architecture. Even an ahead-of-time-compiled asset receives some final specialization on the user's Mac.

### 4. On-device specialization and caching

When RawCullAI loads `.aimodel` or `.aimodelc`, Core AI specializes the asset for the current Mac's hardware and OS. By default `AIModel` caches the result. RawCull may call `AIModel.specialize(contentsOf:options:cache:cachePolicy:)` after installation to control when that work happens and to show accurate preparation progress.

Apple's [Managing model specialization and caching](https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching) guidance has important consequences:

- Cache identity depends on the source asset and `SpecializationOptions`.
- An OS update always invalidates the specialized asset, regardless of cache policy.
- Changing or deleting the source asset can invalidate default-policy cache entries.
- Storage pressure can remove purgeable cached specializations.
- `.persistent` prevents some automatic purging but not OS-update invalidation.
- Removing or replacing a downloaded model should also remove obsolete cache entries.
- If RawCull ever deletes the source asset after specialization, it must use a persistent cache and save `AIModel.bookmarkData`; it must also handle an invalid bookmark by downloading and specializing again.

For the first implementation, retaining the verified source asset and using the default Core AI cache is simpler and more repairable than a bookmark-only design.

## End-to-end lifecycle

```text
Developer or CI
    Official upstream checkpoint at a pinned revision
        -> export with pinned PyTorch and Core AI tooling
        -> optimize and validate output quality
        -> produce selected runtime .aimodel
        -> optionally produce per-architecture .aimodelc variants
        -> generate tokenizer resources and metadata.json
        -> fingerprint the selected asset
        -> archive, hash, sign manifest, and publish

RawCullAI on the user's Mac
    Present model information and applicable terms
        -> obtain required acceptance
        -> choose portable .aimodel or matching .aimodelc variant
        -> download manifest and archive
        -> verify version, signature, size, and checksum
        -> unpack into a private temporary directory
        -> validate PhotoAIKit resource layout and selected-asset fingerprint
        -> optionally pre-specialize through Core AI with visible progress
        -> validate that the provider loads and exposes the expected functions
        -> atomically install the resource directory
        -> enable the corresponding AI capability

Core AI runtime
    Load selected .aimodel or .aimodelc
        -> specialize for this Mac and OS when required
        -> store specialization in AIModelCache
        -> load inference functions and run entirely on device
```

The Model Manager must treat installation as transactional. A failed download, verification, unpacking, validation, specialization, or provider load must not damage an existing working version.

## Required resource layout

PhotoAIKit expects a directory, not a bare model asset. The minimum normalized layout for both CLIP and SAM 3 is:

```text
ModelResource/
├── metadata.json
├── tokenizer/
│   └── tokenizer.json
└── selected-model.aimodel
```

The selected asset may instead be `selected-model.<coreai-architecture>.aimodelc`. Additional tokenizer files such as `tokenizer_config.json`, `special_tokens_map.json`, `vocab.json`, and `merges.txt` may be present when required by the selected tokenizer.

The current screenshot is consistent with developer export directories containing source and optimized `.aimodel` packages and, for SAM 3, an ahead-of-time `.aimodelc`. A production download should be smaller and unambiguous: `metadata.json` must select exactly one runtime asset and the archive should omit unused source or architecture variants.

Conceptual metadata:

```json
{
  "metadata_version": "0.3",
  "kind": "embedding",
  "family": "clip",
  "source_model": "openai/clip-vit-base-patch32",
  "name": "clip-vit-base-patch32_float16_static",
  "preprocessing_version": "clip-srgb-bilinear-chw-v1",
  "configuration_version": "coreai-clip-image-v1",
  "assets": {
    "main": "clip-vit-base-patch32_float16_static.aimodel"
  },
  "asset_fingerprints": {
    "main": {
      "algorithm": "directory-tree-sha256-v1",
      "value": "<sha256>"
    }
  }
}
```

The PhotoAIKit exporter uses `directory-tree-sha256-v1` for package-directory assets such as those shown in Finder and plain `sha256` when the selected asset is a regular file.

PhotoAIKit validates that:

- the candidate is a directory;
- `metadata.json` decodes correctly;
- `assets.main` exists and names an `.aimodel` or `.aimodelc`;
- the selected asset exists;
- `tokenizer/tokenizer.json` exists; and
- the selected asset matches `asset_fingerprints.main` when a fingerprint is supplied.

Production bundles must include a cryptographic fingerprint. PhotoAIKit's legacy size/modification-time fallback is useful for compatibility but is not adequate download-integrity protection.

## Hosting the converted models

The resource archives may be hosted through:

- Apple-Hosted Background Assets;
- separate RawCullAI model repositories on Hugging Face; or
- a RawCull-controlled CDN or download server.

Possible Hugging Face repository names should reflect Core AI rather than Core ML:

```text
RawCullAI/sam3-coreai
RawCullAI/clip-coreai
```

Do not publish mutable `main` download URLs. Every archive must have an immutable RawCullAI model version and upstream revision. If architecture-specific `.aimodelc` files are published, the manifest must map each `AIModel.deviceArchitectureName` value to the correct file, checksum, size, and minimum OS version.

Each release must include:

- Model name and RawCullAI model version.
- Original publisher and upstream repository.
- Exact upstream commit or immutable revision.
- Names and hashes of the source weight files.
- Export and optimization script revisions.
- Python, PyTorch, `coreai-torch`, Core AI optimization, and other dependency versions.
- Core AI deployment target and precision.
- Whether the artifact is portable `.aimodel` or architecture-specific `.aimodelc`.
- For `.aimodelc`, the Core AI architecture name and `coreai-build` command/version.
- Quantization, pruning, partitioning, or other modifications.
- Expected function names, inputs, outputs, preprocessing, and post-processing.
- Supported RawCullAI, PhotoAIKit, Xcode/SDK, and macOS versions.
- Archive, installed-resource, and expected specialization-cache sizes.
- SHA-256 checksum of the complete downloadable archive and the selected asset's fingerprint algorithm and value.
- A signed manifest or equivalent authenticity mechanism.
- Complete applicable licence text.
- Model card, limitations, and attribution.

Publishing a converted model separately from the application is still redistribution. Optional download, local specialization, or storage in a sandbox does not remove the upstream model's licence obligations.

## Apple-Hosted Background Assets

Apple recommends remotely hosting architecture-specific `.aimodelc` assets when that avoids downloading unused variants. [Apple-Hosted Background Assets](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs) can host large assets separately from the app and manage downloads, updates, and compression.

If RawCull adopts this service:

- Confirm that Apple-Hosted Background Assets is available for RawCull's actual distribution channel and current beta/release state.
- Add the required downloader extension and App Group.
- Configure `BAAppGroupID` and `BAHasManagedAssetPacks`; configure `BAUsesAppleHosting` when Apple hosts the packs.
- Use on-demand policy for optional AI models rather than forcing them at first launch.
- Display foreground download progress.
- Treat the system-provided asset-pack URL as read-only and pass a normalized, validated resource-directory URL to PhotoAIKit.
- Keep model licence presentation and acceptance in RawCull; Background Assets does not satisfy third-party licence obligations.
- Test update, removal, low-disk, offline, cancellation, and asset-unavailability behavior.

RawCull-controlled HTTPS downloads remain valid if they provide equivalent integrity, update, recovery, and user-experience guarantees.

## Model Manager user experience

Add an **AI Models** section to RawCullAI Settings. Present the same information as a sheet when a user first chooses an AI feature whose resources are unavailable.

Do not force a multi-gigabyte model download during first launch.

Each model card should show:

- Model and feature name.
- Installed, unavailable, downloading, verifying, preparing, ready, update available, or failed state.
- Original publisher.
- Core AI converter/distributor.
- Exact model version and upstream revision.
- Download size, installed-resource size, and estimated specialization-cache size.
- Minimum free-space requirement.
- Minimum macOS version and supported Mac hardware.
- Processing location, such as "Entirely on this Mac."
- Links to the complete licence, model card, source, conversion details, and privacy information.
- Download and specialization progress with cancellation where the underlying operation supports it safely.
- Install, update, repair, and remove actions as appropriate.

Example:

```text
SAM 3 - Subject Detection

Provider: Meta
Core AI conversion: RawCullAI
Version: 1.0.0
Download size: <verified size>
Installed size: <verified size>
Additional preparation space: <measured estimate>
Requires: macOS 27 and a supported Apple-silicon Mac
Processing: Entirely on this Mac

This optional model is governed by the SAM License.

[View model information] [View complete licence]

[ ] I have read and agree to the SAM License

[Accept and Download]
```

After downloading, use a distinct `Preparing model for this Mac` state for Core AI specialization. Do not label this as `Compiling Core ML model`.

## Separate legal, model, and privacy information

The Model Manager should present three distinct categories.

### Licence

Show the binding terms governing use and distribution of the model. Only this section should require an acceptance checkbox when acceptance is required.

### Model information

Show intended purpose, limitations, accuracy considerations, bias, upstream model card, conversion and optimization details, selected asset type, and known unsupported uses. This is important product information but should not be disguised as a legal agreement.

### Privacy

Explain clearly:

- Who hosts the download.
- That the hosting server or Apple necessarily receives network request metadata.
- Whether a Hugging Face account or OAuth authorization is involved.
- Whether download analytics or telemetry are collected.
- Where the downloaded resource and Core AI specialization cache are stored.
- Whether photographs and embeddings remain local.
- Whether any photo, mask, prompt, embedding, or inference result leaves the Mac.

If all inference is local, state that plainly. Do not claim that no information is transmitted when downloading the model contacts a server.

## Licence acceptance record

When a user accepts a model licence, save a local record containing:

- Model identifier.
- Upstream repository and revision.
- RawCullAI model version.
- Selected asset filename and fingerprint.
- Licence name and published version or date.
- SHA-256 hash of the exact displayed licence text.
- Acceptance timestamp.
- RawCullAI version.

Example:

```json
{
  "model": "sam3-coreai",
  "upstreamRevision": "<immutable-commit>",
  "modelVersion": "1.0.0",
  "asset": "sam3_float16.aimodel",
  "assetFingerprint": {
    "algorithm": "directory-tree-sha256-v1",
    "value": "<sha256>"
  },
  "license": "SAM License",
  "licenseDate": "2025-11-19",
  "licenseSHA256": "<sha256>",
  "acceptedAt": "2026-07-15T12:00:00Z",
  "applicationVersion": "<RawCullAI-version>"
}
```

Require acceptance again if an update changes the licence text or applicable terms. Never preselect the acceptance checkbox. Label the action **Accept and Download**, not merely **Continue**.

## SAM 3

The official SAM 3 repository is [`facebook/sam3`](https://huggingface.co/facebook/sam3). It is gated on Hugging Face and requires a user to sign in, review the conditions, and agree to share contact information before accessing the official files.

The [SAM 3 licence](https://github.com/facebookresearch/sam3/blob/main/LICENSE), last updated November 19, 2025, grants rights to use, reproduce, modify, create derivatives of, and distribute SAM materials. Important conditions include:

- SAM materials and derivatives distributed to a third party must remain subject to the SAM licence.
- A copy of the SAM licence must accompany distributed SAM materials or derivatives.
- Use must comply with applicable law, privacy and data-protection law, trade controls, and prohibited-use provisions.
- The licence contains termination, warranty disclaimer, limitation-of-liability, and indemnification provisions.
- Meta may modify the licence, and continued use after a modification constitutes agreement to the modification.

A RawCullAI Core AI conversion is a modification or derivative and its separate download is redistribution. The converted artifact must include the complete SAM licence and remain under those terms.

Because Meta distributes the official weights through a gated repository, confirm before public release that Meta accepts the proposed RawCullAI redistribution and acceptance flow. The safest approaches remain:

1. Obtain written confirmation from Meta for distribution of a converted Core AI derivative; or
2. Ask whether the converted artifact can be hosted in or linked from an official or approved gated repository.

Until that point is settled, do not publish an ungated public SAM 3 Core AI download.

If users download directly from the official gated repository, use each user's authorization. Never embed a developer Hugging Face token in RawCullAI. Hugging Face documents OAuth for native applications and a `gated-repos` scope in its [OAuth](https://huggingface.co/docs/hub/en/oauth) and [gated-model](https://huggingface.co/docs/hub/en/models-gated) documentation.

## CLIP

"CLIP" identifies a model family, not a single checkpoint or licence. RawCullAI must verify the exact checkpoint selected for similarity scoring.

The current PhotoAIKit exporter supports `openai/clip-vit-base-patch32`. Before release, record:

- Exact Hugging Face repository ID.
- Weight filenames and immutable revision.
- Original publisher and training source.
- Licence that explicitly applies to the weights, not only supporting code.
- Copyright notice.
- Model-card limitations and intended uses.
- Licence status of the Core AI conversion.

OpenAI's original CLIP source repository uses the [MIT licence](https://github.com/openai/CLIP/blob/main/LICENSE), which requires retaining the copyright and licence notice. That does not automatically prove every hosted CLIP or OpenCLIP checkpoint uses the same licence.

If the selected weights are confirmed to be MIT-licensed, RawCullAI may distribute the conversion subject to the MIT notice requirements. Explicit click-through acceptance is generally unnecessary for an MIT licence, but the complete notice must remain accessible under **Third-Party Models**.

Do not release the CLIP model until its exact checkpoint, immutable revision, and weight licence are recorded and reviewed.

## Hugging Face attribution

Hugging Face is the hosting platform and is not automatically the model owner or licensor. Its [Terms of Service](https://huggingface.co/terms-of-service) state that downloaded content remains subject to its accompanying terms and that licence references must not be removed.

Use factual wording such as:

```text
Source repository hosted on the Hugging Face Hub.
```

Do not say a model is "licensed by Hugging Face" unless Hugging Face is the licensor, and do not imply endorsement.

## Sandbox storage and Core AI cache ownership

Use Foundation's Application Support location for RawCull-owned model resources:

```text
Application Support/
└── RawCull/
    └── Models/
        ├── SAM3/
        │   ├── metadata.json
        │   ├── tokenizer/
        │   │   └── tokenizer.json
        │   ├── selected-sam3.aimodel
        │   ├── LICENSE.txt
        │   └── acceptance.json
        └── CLIP/
            ├── metadata.json
            ├── tokenizer/
            │   └── tokenizer.json
            ├── selected-clip.aimodel
            └── LICENSE.txt
```

The current code uses one active SAM3 directory and one active CLIP directory. If the Model Manager installs versioned subdirectories, it must also add an explicit active-version selection mechanism; PhotoAIKit does not discover arbitrary nested versions automatically.

Core AI owns the specialization-cache layout. RawCull should manage it only through `AIModelCache`, never by assuming a filesystem path or deleting cache files directly.

Store transient archives and unpacking output in a private temporary installation directory. Move a verified resource directory into its final location atomically. Exclude large re-downloadable resources from backups, display disk use, and provide removal.

If a separate installer, extension, or second application shares resources or specialized assets, use an App Group and the corresponding entitlements. For shared specializations use `AIModelCache(appGroup:)`.

## Security and integrity

Model downloads are executable inputs to an inference system and must be treated as security-sensitive assets.

Required protections:

- Use HTTPS.
- Pin immutable model versions and upstream revisions.
- Publish expected archive size and SHA-256 checksum in a manifest.
- Authenticate the manifest with a signature or equivalent trusted mechanism.
- Verify the signature before trusting manifest URLs or checksums.
- Verify archive size and checksum before unpacking.
- Reject unexpected files, symlinks, traversal paths, and invalid package layouts.
- Place download and preparation output in private temporary directories.
- Require `metadata.json` to name exactly one intended runtime asset.
- Require and verify `asset_fingerprints.main` for production resources.
- Validate expected Core AI function names, inputs, outputs, shapes, and types.
- Install with an atomic directory replacement and preserve the previous version until validation succeeds.
- Never execute code obtained from a model repository.
- Prefer safe source-weight formats during developer conversion and avoid untrusted pickle artifacts.
- Keep authentication tokens in the macOS Keychain.
- Never ship developer, CI, or repository-owner credentials.

PhotoAIKit's resource fingerprint protects model-derived cache identity, but it does not replace archive-manifest authentication, licence verification, or secure transport.

## Installation state model

Use structured state rather than Boolean flags or display strings. At minimum distinguish:

```text
notInstalled
termsRequired
readyToDownload
downloading(progress)
verifying
unpacking
validatingResources
specializing(progressOrIndeterminate)
validatingProvider
installed(version, assetFingerprint)
updateAvailable(installed, available)
repairRequired(reason)
failed(stage, error)
removing
```

Application termination or cancellation must leave either the previous valid version or no installed model, never a partial directory presented as ready.

Feature availability must be derived from PhotoAIKit's validated capability and successful provider creation, not merely from path existence. A missing Core AI specialization after an OS update is normally a recoverable `preparing` condition, not proof that the downloaded model is corrupt.

## Updates and removal

Model updates should be independent of RawCullAI application releases, but every artifact needs a RawCullAI and PhotoAIKit compatibility range.

For an update:

1. Fetch and authenticate the manifest.
2. Compare model version, compatibility, architecture, upstream revision, asset fingerprint, and licence hash.
3. Present release notes, total disk requirement, and licence changes.
4. Obtain new acceptance if applicable terms changed.
5. Download into a temporary or versioned inactive directory.
6. Validate resources and optionally pre-specialize the new selected asset.
7. Validate the provider.
8. Atomically switch the active resource.
9. Remove the old Core AI cache entry through `AIModelCache` and then remove old resources.

Removing a model should:

- Disable only the feature requiring it.
- Release loaded provider/model references.
- Remove Core AI cache entries for the selected source asset through `AIModelCache`.
- Remove the downloaded resource directory.
- Preserve or remove acceptance according to the intended reinstall flow.
- Leave unrelated RawCullAI settings, photo metadata, masks, embeddings, and non-model caches untouched unless the user separately chooses to delete derived AI data.

If the licence terminates or a model must be withdrawn, the manifest service may mark a version as revoked. RawCullAI must not silently delete a locally installed model without a documented product and legal decision, but it may block updates or warn that continued use is unsupported or impermissible.

## Reliability and resource management

Installation may temporarily require space for the archive, unpacked resource, selected `.aimodel` or `.aimodelc`, the previous version, and Core AI's specialized cache. Measure actual peak use on representative Macs; do not estimate only from the selected model's Finder size.

The Model Manager must handle:

- Resumable or safely restartable downloads.
- Network loss and HTTP errors.
- Authentication expiration and gated access denial.
- Checksum, signature, and asset-fingerprint failures.
- Corrupt archives and invalid resource layouts.
- Unsupported Core AI architecture or macOS version.
- Specialization failure or cache eviction.
- OS-update cache invalidation.
- Provider-interface mismatch.
- Insufficient disk space.
- Cancellation and application termination.
- Repair after manual deletion or disk corruption.

Operational errors should remain structured and diagnosable. Do not collapse them into a generic "model unavailable" message.

## Core AI, Xcode 27, and macOS 27 beta constraints

Core AI is beta technology as of this review. These are platform and release constraints, not a new licence for the SAM 3 or CLIP weights.

### Toolchain and runtime

- RawCullAI's pinned PhotoAIKit revision requires Xcode 27, Swift tools 6.4, Swift 6 language mode, and macOS 27.
- Core AI is designed for Apple silicon. RawCull already targets arm64, but model compatibility and memory requirements still need testing across supported Mac families.
- Xcode 27 beta 3 itself requires macOS Tahoe 26.4 or later according to Apple's [Xcode support matrix](https://developer.apple.com/support/xcode/).
- `.aimodelc` artifacts must be generated with the current compatible `coreai-build`; early beta-generated assets may be invalidated by later seeds.

### Beta distribution

As of July 7, 2026, Apple says builds made with Xcode 27 beta 3 and macOS 27 beta 3 SDK can be distributed through TestFlight for internal and external testing. Apple's [App Store Connect release notes](https://developer.apple.com/help/app-store-connect/release-notes/) do not yet establish customer App Store distribution for these beta builds.

Before a production release:

- Confirm the intended App Store, Developer ID/notarized, or other distribution channel accepts the exact Xcode and SDK build.
- Rebuild and revalidate with the final or accepted release toolchain.
- Re-export or recompile models if the final Core AI format or compiler requires it.
- Re-run correctness, performance, cache, update, and low-disk tests on the final macOS release.
- Review the current [Apple developer agreements](https://developer.apple.com/support/terms) and distribution requirements.

Do not describe beta TestFlight acceptance as approval for general customer distribution.

### Current beta caveats

Apple's [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) currently identify Core AI issues that can vary by seed. At the time of review:

- Models exported with affected early `coreai-torch` versions may fail specialization; use the fixed or later version identified by the current release notes.
- `.aimodelc` files produced by affected early Xcode 27 betas may fail and need recompilation with a newer beta.
- Core AI behavior with Metal API Validation and some dynamic/control-flow models has changed across seeds.
- Large-model load and memory behavior is still being improved and must be measured on every supported Mac class.

Record the Xcode build, macOS build, `coreai-torch` version, Core AI optimization version, `coreai-build` invocation, and PhotoAIKit/coreai-models revisions for every test artifact.

### Background execution entitlement

The macOS 27 beta release notes identify a new entitlement for continued-processing inference that uses the Neural Engine in the background: `com.apple.developer.background-tasks.continued-processing.inference`.

RawCull should not add it pre-emptively. Determine whether any future helper or background task actually performs Core AI inference after the app leaves the foreground, then verify entitlement eligibility, signing, App Review implications, and behavior on the current macOS seed. Model downloading through Background Assets is separate from inference execution.

### No framework-specific model redistribution grant

Nothing in the Core AI API documentation grants RawCull the right to redistribute Meta or OpenAI model weights. Core AI governs the runtime and asset format; upstream model licences govern the weights and converted derivatives. Apple's developer agreements, privacy requirements, export/compliance processes, signing, notarization, and distribution rules continue to apply to the application and any Apple-hosted assets.

## Testing requirements

Use Swift Testing and include tests for:

- Manifest decoding, signature verification, and immutable-version selection.
- Archive and selected-asset size/checksum verification.
- PhotoAIKit `metadata.json` decoding and `assets.main` selection.
- Rejection of unsupported extensions and missing tokenizer resources.
- `.aimodel` and supported `.aimodelc` resource validation.
- Architecture-to-`.aimodelc` selection using `AIModel.deviceArchitectureName`.
- Asset-fingerprint mismatch detection.
- Licence-hash comparison and reacceptance decisions.
- Acceptance-record persistence.
- State transitions and cancellation.
- Interrupted download and restart/resume.
- Archive traversal, symlink, and unexpected-file rejection.
- Atomic installation and rollback.
- Core AI specialization success, failure, cache hit, eviction, and OS-update recovery behavior.
- Expected inference functions, descriptors, inputs, outputs, and shapes.
- Insufficient disk space including specialization-cache overhead.
- Model removal, cache-entry deletion, and repair.
- Compatibility checks and concurrent installation requests.
- Token expiration without credential exposure.
- Capability enablement only after resource and provider validation.

Release validation must compare the Core AI output against the pinned upstream model on representative inputs, measure peak memory and latency, and verify subject detection and similarity quality on representative RawCull photographs.

## Release checklist

No model may be published until all applicable items are complete.

### Identity and provenance

- [ ] Exact upstream repository and immutable revision recorded.
- [ ] Source weight files and hashes recorded.
- [ ] Export and optimization source revisions pinned.
- [ ] Python, PyTorch, `coreai-torch`, and optimization versions recorded.
- [ ] RawCullAI model version assigned.
- [ ] PhotoAIKit and `apple/coreai-models` revisions recorded.

### Licence and policy

- [ ] Licence confirmed to apply to the actual weights.
- [ ] Redistribution and derivative rights confirmed.
- [ ] Complete licence included with the artifact.
- [ ] Required notices and attribution included.
- [ ] Model-card limitations reviewed and summarized.
- [ ] SAM 3 gated redistribution confirmed with Meta or qualified counsel.
- [ ] CLIP checkpoint and weight licence explicitly identified.
- [ ] Acceptance UI reviewed against the exact published terms.
- [ ] Privacy statement matches actual hosting, telemetry, cache, and inference behavior.
- [ ] Current Apple agreements and distribution-channel requirements reviewed.

### Core AI artifact

- [ ] Selected `.aimodel` builds reproducibly enough to audit.
- [ ] Optimization changes and quality comparisons documented.
- [ ] Any `.aimodelc` maps to the exact Core AI architecture and minimum OS.
- [ ] Any `.aimodelc` was built with the approved release toolchain.
- [ ] `metadata.json` selects exactly one intended runtime asset.
- [ ] Required tokenizer files are present.
- [ ] `asset_fingerprints.main` is cryptographic and verified.
- [ ] Expected functions, inputs, outputs, types, and shapes are validated.
- [ ] Unused source models and architecture variants are excluded from end-user archives.

### Download and security

- [ ] Archive contains only expected files.
- [ ] Archive size and SHA-256 are published.
- [ ] Manifest is authenticated.
- [ ] Download uses HTTPS and immutable URLs.
- [ ] No credentials, development paths, or private metadata are included.
- [ ] Background Assets configuration and App Group are correct if used.

### Product readiness

- [ ] Download, installed-resource, cache, and peak free-space sizes are accurate.
- [ ] Progress, cancellation, retry, repair, update, and removal work.
- [ ] Specialization is described as preparation for the Mac, not Core ML compilation.
- [ ] Previous version survives a failed update.
- [ ] OS-update cache invalidation recovers cleanly.
- [ ] Licence changes trigger new acceptance.
- [ ] Third-party licence remains accessible after installation.
- [ ] Feature remains disabled until resources and provider are ready.
- [ ] Local-processing and network-use statements are accurate.
- [ ] Final supported macOS versions and Apple-silicon hardware are tested.

### Beta release gate

- [ ] Current Xcode 27 and macOS 27 release notes reviewed.
- [ ] Current Core AI known issues evaluated against CLIP and SAM 3.
- [ ] Intended distribution channel accepts the exact toolchain/SDK build.
- [ ] Models re-exported or recompiled if the current seed requires it.
- [ ] Final validation repeated on the release OS and toolchain before customer distribution.

## Final recommendation

RawCullAI should provide a polished Model Manager and distribute versioned, verified **Core AI resource archives**. The current canonical runtime artifact is an optimized `.aimodel`; architecture-specific `.aimodelc` should be treated as an optional download and startup optimization, not as Core ML output.

RawCullAI should validate the resource directory through PhotoAIKit, optionally prepare the selected asset through Core AI, retain the source asset for simple recovery, and let `AIModelCache` own specialized runtime data. It should never document or implement the old `.mlpackage -> .mlmodelc` workflow for these models.

The release gates are:

1. Written confidence that distributing the SAM 3 Core AI derivative is compatible with Meta's licence and gated release process.
2. Identification and review of the exact CLIP checkpoint licence as it applies to the weights.
3. Validation of model output, memory, specialization, cache, and update behavior with the final accepted Xcode 27 and macOS 27 toolchain.
4. Confirmation that the intended distribution channel supports the exact Xcode/SDK build and, if used, the chosen Background Assets configuration.

Neither model should be published until its corresponding legal, technical, and beta-distribution gates are resolved and recorded in the release manifest.
