# RawCull 3.0.0 stabilization baseline

Captured on 2026-08-04 at 06:48 CEST before product-code changes.

## Source boundary

- Stabilization branch: `codex/version-3.0.0-stabilization`
- Baseline commit: `b8b4e2eb952fc8a7d6037996a1b5fa81d34ca646`
- Local and remote `version-3.0.0`: `b8b4e2eb952fc8a7d6037996a1b5fa81d34ca646`
- Local and remote `main`: `2857a6b3a095425b06bbe8c8f757e32f2cd07664`
- Architecture: `arm64`
- Package lock checksum (SHA-256): `07ac998bb08e7caccdebdc049cb24dc5e26be8c16a6e83c68f5eabdd9eba4345`
- Model manifest checksum (SHA-256): `d422ff5c5fe39370212e704deebd1300587ca9505f605af9ffd2d6960aa5f87e`
- Model notices checksum (SHA-256 over sorted per-file hashes): `62dadd0d7064a52ce3c53b4becc0199f965300fe04e2543c7473268b8354013c`
- App entitlements checksum (SHA-256): `0756f090ea4ce5c69ea9cd2790fbf4db4645eaa93ef06da2458f1dbd46ccfa87`
- Model-downloader entitlements checksum (SHA-256): `cc70df846efb7bf54a64ae89b11e6da466248c86d9cbead1b37a6c11a8aa14d5`

The stabilization source is ahead of `main`; no merge or cherry-pick from the
2.3.4 line was performed.

## Toolchain and build inputs

- Xcode 27.0 beta (`27A5228h`)
- Apple Swift 6.4 (`swiftlang-6.4.0.27.1`, `clang-2100.3.27.1`)
- macOS 27.0 (`26A5388g`)
- App language mode: Swift 6, MainActor default isolation, Approachable
  Concurrency enabled
- Test strict-concurrency mode: complete
- App deployment target: macOS 27.0
- App marketing version/build: 3.0.0 (231)
- Model-downloader marketing version/build: 2.3.3 (230)
- Bundle identifiers: `no.blogspot.RawCull` and
  `no.blogspot.RawCull.ModelDownloader`

The model-downloader version/build mismatch is a baseline release warning:
Xcode reports that extension build 230 must match containing app build 231.
Phase 8 owns metadata alignment after build-number availability is confirmed.

## Resolved AI package inputs

- PhotoAIKit: revision `2cb07d604beee3549df4d361a5d48b3e9506fb87`
- Apple coreai-models: revision
  `bffc38fe48f50e4e962ac9772b64a5b55a605286`
- PhotoAnalysisKit: 1.2.0
- RawParserKit: 1.2.8
- RawCullCore: 1.1.2

`Package.resolved` is authoritative for the complete transitive graph.

## Available model-state matrix

The repository contains model manifests, notices, provenance, and bundled
licence text, but no production model binaries. No live user model directory
or live `UserDefaults` domain was inspected or modified.

| State | Baseline availability | Evidence |
|---|---|---|
| No downloaded models | Available | Clean repository/model-resource state |
| Valid DataComp CLIP | Not locally available | Descriptor and isolated validation tests exist |
| Valid OpenAI CLIP | Not locally available | Descriptor and isolated validation tests exist |
| Valid SAM 3 | Not locally available | Descriptor and isolated download/licence tests exist |
| Corrupt/incomplete model | Simulated in isolated tests | Validation cache invalidation and failure-state coverage |
| Unaccepted licence | Simulated in isolated tests | Download remains gated until acceptance |
| Vision fallback | Available | Built-in backend and typed fallback tests |

All three production download descriptors are intentionally release-blocked by
the current licence audit, and the self-hosted manifest URL remains a
placeholder. This is retained as a release blocker rather than bypassed.

## Persistence fixture snapshot

The existing suites construct disposable directories and unique settings files
under the system temporary directory. They do not use the live RawCull
application-support or cache roots. Fixture/source hashes at the baseline are:

| Boundary | SHA-256 fixture/source snapshot |
|---|---|
| Ratings, saved files, and culling decisions (`CullingModelTests.swift`) | `1536a924e3bdb224cf3b1dc8e72b588c612f0b7b17e1afe05a402d14b66fc89e` |
| Isolated cache/settings/saved-file helpers (`TestIsolationHelpers.swift`) | `00abfbaaf6cd64aed4d393fa5c4b431e16196dd660eed5af697bf296ebd25e47` |
| Typed per-file artifacts (`PerFileAnalysisArtifactStoreTests.swift`) | `306e18455b5444134964a152c921ae151cbfdc8ae20b4d86b0dd10453d000dc1` |
| Backend migration and legacy burst fixtures (`PhotoAIKitSimilarityMigrationTests.swift`) | `c5adef0530b09744b371027d55d01cfafa445b5c8ec76bfb37167ae38f79e068` |
| Semantic state (`RawCullSemanticSearchTests.swift`) | `a282f6638d57e16584488959f80260c9f04fbcf97503c8525aceb018115de786` |
| Subject masks and Deep Review (`DeepAIReviewFeatureTests.swift`) | `9abb628783aec914a161565d718eae5e469d0dd9e7704675b5ae4a54a8c34e3d` |
| Model download/licence acceptance (`RawCullAIModelDownloadsTests.swift`) | `ef3d9a142bfe71e02fc6da10017c8806b085839005c7bff75600e19441b0ff16` |

Production format snapshots were also anchored by source hashes for
`BurstAnalysisCache.swift` (`108fb69f...`),
`PerFileAnalysisArtifactStore.swift` (`5fa9a6c3...`), and
`RawCullAIModelLicenceAcceptance.swift` (`db8d16b2...`). No format or live
persistent data changed in this phase.

## Baseline gates

| Gate | Unique tests | Concrete executions | Result |
|---|---:|---:|---|
| `make test-smoke` | 71 | 71 | Failed: 70 passed, 1 failed |
| `make test-full` with TSan | 290 | 315 | Failed: 314 passed, 1 failed; no TSan runtime warning reported |
| `make test-performance` | 1 | 1 | Passed |
| Exact-package arm64 Release build | n/a | n/a | Passed with extension build-number warning |

The performance command names two tests, but only the data-race test executed;
the PhotoAIKit benchmark selector did not match its Swift Testing identifier.
Phase 3 owns this gate-manifest defect.

The same existing test failed in smoke and full TSan:

- `PhotoAnalysisKitIntegrationTests/RawCull focus model analyzes through package Metal pipeline()`
- Assertion: `result.breakdown.finalScore > 0`
- Observed: the result has a mask and breakdown, but the synthetic checkerboard
  scores zero with the current PhotoAnalysisKit/Metal implementation.
- Owner: RawCull focus/scoring integration boundary in this stabilization
  stream; Phase 3 must establish a deterministic integration assertion or fix
  a proven production regression before any final green-gate claim.

The smoke command returned exit 65 and `make` returned nonzero, proving that
the current gate does not mask this failure.

## Rollback statement

Phase 0 changed only this ledger. It did not change code, packages, project
settings, model resources, model identities, cache contents, or live persistent
data.
