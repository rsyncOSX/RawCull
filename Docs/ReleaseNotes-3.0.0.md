# RawCull 3.0.0 release notes

RawCull 3 introduces an optional local-AI layer while retaining the core RAW
culling workflow. It requires macOS 27 on Apple Silicon.

## Highlights

- Search a catalog with natural-language descriptions when a validated local
  CLIP model is selected.
- Use DataComp or OpenAI CLIP embeddings for similarity and burst grouping.
- Run SAM 3 Deep Review for subject masks and subject-aware winner evidence.
- Keep using Apple's built-in Vision feature prints for similarity when the
  selected CLIP model is absent or invalid. Vision requires no model download.
- Reuse backend-typed embeddings and subject masks without mixing results from
  different models or pipeline signatures.
- Load histograms and thumbnails with latest-result and replacement-safe cache
  behavior, and display Actual Pixels at one source pixel per display point.
- Navigate the culling and AI interfaces with improved keyboard and VoiceOver
  semantics.

## Models and storage

CLIP and SAM 3 are optional local model bundles. They are not included in the
application or uploaded to an inference service. A compatible bundle contains
`metadata.json`, an `.aimodel` or `.aimodelc` asset, and every resource named by
its manifest. Manual bundles live below `RawCull/Models` in the user's
Application Support directory; sandboxed and non-sandboxed paths are listed in
the project README.

Semantic search needs a valid CLIP model. SAM 3 Deep Review needs a valid SAM 3
bundle. Model binaries, embeddings, and masks may require substantial disk
space; exact archive and installed sizes are not published because the three
download packs are not yet release-ready. The first use of a portable Core AI
model can also take longer while macOS specializes it for the current Mac.

## Known limitations

- Managed Background Assets uses a non-routable placeholder manifest. The
  in-app download flow remains disabled until archive checksums, sizes,
  provenance, and redistribution requirements are complete.
- DataComp CLIP lacks a cryptographic binding from the converted asset to its
  exact source checkpoint. OpenAI CLIP still needs immutable source-revision
  and checkpoint-licence verification. Ungated SAM 3 redistribution still
  needs approval against Meta's SAM License and gated access conditions.
- Without CLIP, similarity falls back to Vision and semantic search explains
  that it is unavailable. Without SAM 3, Deep Review explains that it is
  unavailable. Core culling, rating, preview, and export remain usable.
- VoiceOver traversal, clean-account installation, model-download resume, and
  the real-model/hardware matrix remain manual release gates.

## Release engineering record

- Marketing version: 3.0.0
- Provisional build: 300; App Store Connect availability must be confirmed
  before archive or upload
- Minimum system: macOS 27, Apple Silicon (`arm64`)
- Bundle identifier: `no.blogspot.RawCull`
- Stabilization source before this metadata phase:
  `a62f8a9a627fb8f313174b3dcb4135ccb49a4dfe`
- Package lock SHA-256:
  `07ac998bb08e7caccdebdc049cb24dc5e26be8c16a6e83c68f5eabdd9eba4345`
- Model manifest template SHA-256:
  `d422ff5c5fe39370212e704deebd1300587ca9505f605af9ffd2d6960aa5f87e`
- Model notice catalog aggregate SHA-256:
  `4b14bce3e3ee9f45d82a4c52a0aee8b1d481a3c009ca423485f732f9ea86f656`
- Signed artifact, notarization, stapling, Gatekeeper, final artifact SHA-256,
  and immutable tag: pending the Phase 10 release handoff

The model runtime and licence checksums recorded for this release are audited
in [`ModelAssets/README.md`](../ModelAssets/README.md). They are provenance
evidence, not hashes of downloadable release archives.
