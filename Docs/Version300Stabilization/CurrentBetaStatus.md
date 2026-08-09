# RawCull 3.0.0 current beta status

This file is the current status summary for active Xcode 27 beta development.
The numbered phase documents are historical ledgers for their named commits;
their build numbers, test counts, and checksums must not be treated as
permanent repository invariants.

## Current checked-in configuration

- Marketing version: 3.0.0
- App and model-downloader build: 301
- Deployment target: macOS 27.0
- Architecture: arm64
- Smoke enumeration baseline: 173 unique identifiers and 186 concrete
  invocations
- Performance enumeration baseline: 2 unique identifiers
- `Package.resolved` SHA-256 beta snapshot:
  `f2d3b6bb5b1d58745a6094ad6261239260d68960725d366f29fb423e241d5036`

The package checksum records the currently reviewed dependency snapshot. It is
expected to change when Xcode refreshes the lock file during beta development.
Review and commit the lock-file diff, then update this snapshot. Freeze and
record it again only for a final release candidate.

## Model download scope

DataComp CLIP is the only model currently included in the production managed
download catalogue. OpenAI CLIP and SAM 3 remain disabled and release-blocked;
their descriptors, licences, and implementation are retained without exposing
their downloads. This beta-status cleanup does not alter those blockers.

The enabled DataComp provenance catalog still records an unresolved source
binding audit. Release preflight therefore remains fail-closed until that
evidence is deliberately resolved; beta development and ordinary test targets
do not depend on release preflight.

## Release-candidate boundary

The current branch is not represented by the existing `v3.0.0` tag. Before a
release candidate is archived, the release owner must reconcile that tag,
identify and preserve the authoritative 2.3.4 release reference, select one
clean commit, and run smoke, full TSan, performance, and the exact Release build
on that commit. Interactive model, RAW, VoiceOver, installation, upgrade,
signing, notarization, and artifact-hash evidence remains final-RC work rather
than a blocker for ongoing beta development.
