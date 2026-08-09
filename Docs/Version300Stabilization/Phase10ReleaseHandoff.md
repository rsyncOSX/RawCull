# Phase 10 — independent 3.0.0 release handoff

> Historical ledger: this was a blocked handoff snapshot, not the current beta
> source of truth. Its hashes remain useful for reproducing that commit but are
> not expected to match later Xcode-generated beta inputs.

## Handoff status

RawCull 3.0.0 is **blocked before archive**. This phase prepares a fail-closed
handoff; it does not archive, upload, notarize, publish, tag, or remove any
branch. The Phase 10 input is
`28cfdf532488e4e188432a2969fc24516922a2a7` on
`codex/version-3.0.0-stabilization`. The commit containing this ledger and the
release-tooling safeguards is handoff evidence, not a release tag target.

The last repeatable automated gate commit is
`c86906b2864d2bf32418318a4c92fd2309a8938d`; Phase 9's documentation-only
evidence commit follows it. Once every manual and external blocker is closed,
the four ordered Phase 9 gates must run again on the exact clean commit that
will be tagged, with no subsequent source edit.

## Inputs frozen for this handoff snapshot

| Input | SHA-256 |
|---|---|
| `Package.resolved` | `07ac998bb08e7caccdebdc049cb24dc5e26be8c16a6e83c68f5eabdd9eba4345` |
| Model manifest template | `d422ff5c5fe39370212e704deebd1300587ca9505f605af9ffd2d6960aa5f87e` |
| Application entitlements | `0756f090ea4ce5c69ea9cd2790fbf4db4645eaa93ef06da2458f1dbd46ccfa87` |
| Model-downloader entitlements | `cc70df846efb7bf54a64ae89b11e6da466248c86d9cbead1b37a6c11a8aa14d5` |
| Export options | `6acb0a7c0ccca028715abfdd55389c5848616b2d33140a2d0ffb403ea4f97c64` |

The archive target now names the project, scheme, Release configuration,
arm64 macOS destination, and `-onlyUsePackageVersionsFromResolvedFile`. It
cannot silently resolve a different package graph from the tested build.

## Fail-closed release tooling

`make build` now runs `release-preflight` before its destructive clean or any
archive/notarization operation. The preflight refuses to continue when:

1. the worktree is dirty;
2. neither `v2.3.4` nor `2.3.4` exists as an immutable historical tag;
3. a model provenance catalog still has `release_status: blocked`; or
4. production model descriptors still lack archive hashes or remain blocked.

The DMG workflow staples and validates the ticket, verifies the disk image,
then writes `RawCull.3.0.0.dmg.sha256`. After publication and download,
`make verify-downloaded-dmg DOWNLOADED_DMG=/path/to/file.dmg` compares the
downloaded bytes with that recorded hash.

Dry-run inspection proves the archive command contains the exact-package
flags and that hash generation happens after DMG notarization/stapling. The
preflight was also invoked before this commit and correctly refused the dirty
handoff worktree. It must be invoked again from the committed clean state; it
is expected to remain red on the missing historical tag and blocked model
evidence.

After the tooling and documentation edits, `make test-smoke` passed 173 unique
identifiers and 186 concrete executions with no failures, skips, or runtime
warnings.

## Signing and distribution inventory

- A valid Developer ID Application identity and a valid Apple Development
  identity are present in the local keychain.
- `exportOptions.plist` selects `mac-application`, automatic signing, team
  `93M47F4H9T`, and Swift-symbol stripping.
- The project enables hardened runtime, sandboxing, and the shared Managed
  Background Assets app group for the app and extension.
- The Phase 9 Release build was Apple Development signed. No Developer ID
  distribution archive was produced or verified.
- The existing release workflow signs with hardened runtime, verifies the app
  signature, submits the app and DMG to Apple, staples them, and assesses the
  app with Gatekeeper. Nested app/extension identities and entitlements must be
  inspected on the actual exported artifact; the presence of a keychain
  identity is not signing evidence.
- No DMG, ZIP, or XCArchive is checked into this working tree, so there is no
  final artifact hash to publish or reproduce.

## Phase 10 gate state

| Required handoff action | State | Evidence/blocker |
|---|---|---|
| Freeze exact green AI commit without a new 2.3.4 merge | Partial | Stabilization commits introduced no new 2.3.4 merge; exact tag commit still awaits final manual gates |
| Archive, sign, verify entitlements/model access, notarize, staple, Gatekeeper, clean install, and upgrade | Blocked | Phase 9 real-model/manual matrix is incomplete; no distribution artifact was created |
| Confirm App Store metadata and build number | Blocked | Build 300 is provisional; the available browser session was not authenticated |
| Hash, publish, redownload, and reproduce the signed DMG | Tooling ready; artifact blocked | Hash and comparison targets exist, but there is no signed DMG |
| Tag exact tested commit as `3.0.0` | Not performed | Final release commit is not green across the complete manual matrix |
| Preserve 2.3.4 tag/artifacts before branch removal | Blocked | Local and remote `version-2.3.4` branches both point to `f2f86b66fedbda0cf5fc9dd4f0c3f8071ff89bdf`, but no 2.3.4 tag or artifact exists in this checkout |

The current 2.3.4 branch tip contains planning/handoff documentation and must
not be assumed to be the historical release artifact commit. The release
owner must identify the authoritative shipped 2.3.4 commit and preserved
artifact before creating or pushing a tag. No branch is eligible for removal.

## Operator sequence after blockers close

1. Resolve all three model provenance/licence blockers, generate real asset
   packs and immutable archive hashes/sizes, configure the selected hosting
   path, and rerun metadata/model contract tests.
2. Complete the real-model, real-RAW, hardware/OS, download-resume, VoiceOver,
   clean-account, and 2.3.4 upgrade matrix from Phase 9.
3. Identify and preserve the authoritative 2.3.4 release commit and artifacts;
   create/push its immutable tag only with release-owner approval.
4. Sign in to App Store Connect and confirm build 300 is unused. If it is not,
   update app and extension together and rerun Phases 8 and 9.
5. Select the final 3.0.0 commit, require a clean worktree, record its commit
   and input hashes, then rerun smoke, full TSan, performance, and the exact
   Release build in the prescribed order.
6. Run `make release-preflight`, then `make build`. Preserve the archive,
   signing identities, entitlements, notarization IDs/logs, stapler validation,
   Gatekeeper assessment, clean-install evidence, and upgrade evidence.
7. Publish the DMG and `.sha256` together, download the public artifact, and
   reproduce the hash with `make verify-downloaded-dmg`.
8. Only after every item is green, tag the exact tested commit as `3.0.0`,
   verify the tag's commit ID, and push it with release-owner approval.

Do not weaken or bypass `release-preflight` to make an artifact. A red model,
manual, signing, notarization, hash, App Store, or historical-preservation gate
keeps the release blocked.
