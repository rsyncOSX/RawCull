# Phase 8 — 3.0.0 metadata and AI documentation

> Historical ledger: this file records the Phase 8 commit and its build 300
> artifacts. The active Xcode 27 beta uses build 301. Checksums below are
> snapshots of the recorded commit, not invariants for later beta commits.

## Scope

This phase aligns local application and downloader-extension metadata, makes
the complete resolved package graph reviewable, audits checked-in model-asset
evidence, and supplies 3.0.0 release notes. It does not publish models, upload a
build, sign or notarize a distribution artifact, or claim that unavailable
manual release gates passed.

The inspected stabilization input was
`a62f8a9a627fb8f313174b3dcb4135ccb49a4dfe` on
`codex/version-3.0.0-stabilization`. The commit containing this ledger is the
Phase 8 source commit; Phase 10 must record the exact final green commit and tag
without editing source after the gates.

## Metadata decision and verification

Build 300 was selected provisionally for RawCull 3.0.0 instead of copying the
2.3.4 build 231. The app and Managed Background Assets extension now use the
same marketing version and build in Debug and Release. Project, application,
test, and extension deployment settings are macOS 27; project architectures
are restricted to arm64.

The built Debug and exact-package Release products were inspected directly.
Both app bundles and both embedded extensions report the table values below,
and `lipo` reports arm64 for every executable. The prior extension/build
mismatch warning is no longer emitted.

| Field | RawCull | Model downloader extension |
|---|---|---|
| Marketing version | 3.0.0 | 3.0.0 |
| Build | 300 (provisional) | 300 (provisional) |
| Minimum macOS | 27.0 | 27.0 |
| Bundle identifier | `no.blogspot.RawCull` | `no.blogspot.RawCull.ModelDownloader` |
| Hardened runtime | Enabled | Enabled |
| Sandbox | Enabled | Enabled |
| App group | `group.no.blogspot.RawCull.model-assets` | `group.no.blogspot.RawCull.model-assets` |

`RawCull-Info.plist` derives version, build, identifier, and minimum system
from these build settings. The About window derives its displayed version and
build from the built bundle and now describes optional CLIP/SAM 3 plus the
built-in Vision fallback.

An App Store Connect lookup was attempted with the available in-app browser,
but no authenticated session or local App Store Connect CLI was available.
Therefore build 300 availability is explicitly **not verified**. Archive and
upload remain blocked until a signed-in operator confirms that 300 is unused;
if it is unavailable, update app and extension together and rerun this phase's
metadata tests and both Debug and Release builds.

## Package graph audit

The README now includes every identity in the 3.0.0 `Package.resolved`, using
the exact resolved version or full revision. This includes revision-pinned
PhotoAIKit, `coreai-models`, and `xgrammar`, plus the transitive tokenizer,
template, grammar, JSON, networking, cryptography, and concurrency support
packages. A smoke test compares every lock-file pin with a single README table
row so package documentation cannot silently drift.

Package lock SHA-256:
`07ac998bb08e7caccdebdc049cb24dc5e26be8c16a6e83c68f5eabdd9eba4345`.

## Model asset audit

`ModelAssets/manifest.template.json`, the production download catalog, and the
model-path resolver agree on three asset-pack identifiers and destinations.
Both entitlements use the manifest's app group. The checked-in Info.plist keeps
self-hosting disabled with `example.invalid`, so downloads cannot accidentally
be released from the template.

Every provenance catalog remains `release_status: blocked`. Referenced notice
files exist and their SHA-256 values match the catalogs and bundled licence
texts. All application descriptors intentionally lack a release archive hash,
download size, and installed size. The audited evidence and blocker for each
model are tabulated in `ModelAssets/README.md`.

No model archive or binary is checked in, so no real CLIP or SAM 3 model was
exercised during this repository-only phase. Recorded MLIRB hashes describe
conversion provenance only. The no-model/Vision fallback and synthetic model
contract tests are automated; valid DataComp, OpenAI, and SAM 3 binaries remain
Phase 9 manual matrix inputs.

## Toolchain and artifact state

- Xcode 27.0 (`27A5228h`)
- Swift 6.4 (`swiftlang-6.4.0.27.1`)
- macOS 27.0 (`26A5388g`), arm64
- Model manifest template SHA-256:
  `d422ff5c5fe39370212e704deebd1300587ca9505f605af9ffd2d6960aa5f87e`
- Notice catalog aggregate SHA-256:
  `4b14bce3e3ee9f45d82a4c52a0aee8b1d481a3c009ca423485f732f9ea86f656`
- Debug focused tests and the Release build were development-signed with the
  available Apple Development identity. Their embedded app and extension
  entitlements contain the sandbox and shared app group. Strict code-signature
  verification reports `CSSMERR_TP_NOT_TRUSTED`, so this is build evidence,
  not a distributable signature.
- Distribution signing identity, archive, notarization, stapling, Gatekeeper
  assessment, final DMG SHA-256, clean download reproduction, and tag: not
  performed; owned by Phase 10 after all Phase 9 gates are green

## Release blockers carried forward

1. Confirm build 300 is unused in App Store Connect.
2. Resolve every model redistribution blocker before enabling downloads.
3. Complete the real-model/backend, macOS 27, hardware/memory, clean-account,
   upgrade, VoiceOver, download-resume, and licence-acceptance matrix.
4. Produce, sign, notarize, staple, assess, hash, redownload, and re-hash the
   final distribution artifact without editing source after the green commit.
