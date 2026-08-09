# Phase 9 — integrated AI and compatibility regression

> Historical ledger: the green results below apply only to commit `c86906b`.
> Later beta commits require fresh gates before they can become a release
> candidate.

## Outcome

The automated source gates are green on
`c86906b2864d2bf32418318a4c92fd2309a8938d`. The production release matrix is
**not green** because real model bundles and several signed interactive,
hardware, operating-system, installation, and distribution inputs are not
available in this checkout. Phase 10 must not archive, upload, notarize, or tag
this commit as a release until the blockers in this ledger are closed.

The final ordered gate sequence started from a clean worktree on
`codex/version-3.0.0-stabilization`. `version-2.3.4` is not an ancestor of this
commit; no 2.3.4 merge was introduced.

## TSan gate repair discovered during regression

The first full TSan run from the Phase 8 commit exposed a test-harness
scheduling race in the fixed-catalog thumbnail contention profile. The
coalesced-waiter counter could reach `N - 1` before the single producer entered
the suspended image loader. The test then observed zero loader calls, released
no loader continuation, and waited until the test runner timed out. The result
bundle recorded the failed expectation at
`ThumbnailContentionTests.swift:104`, no TSan runtime warning, and a 9 minute
28 second test duration.

The fixture now waits for both `N - 1` coalesced callers and the one admitted
producer/waiter before checking or releasing the loader. The focused TSan
suite passed all eight concrete executions, including the 12, 120, and 1,200
request profiles. The repair is independently committed as
`c86906b test: stabilize thumbnail contention under TSan`.

## Ordered clean-commit gates

| Gate | Unique identifiers | Concrete executions | Result |
|---|---:|---:|---|
| `make test-smoke` | 173 | 186 | Passed; no failure, skip, or runtime warning |
| `make test-full` with TSan | 332 | 359 | Passed; no failure, skip, runtime warning, or TSan diagnostic |
| `make test-performance` | 2 | 2 | Passed; both intended selectors executed |
| Exact-package arm64 Release build | n/a | n/a | Passed |

The performance run indexed 12 synthetic Vision images in 0.140 seconds and
computed 500 distances in 0.020 seconds on the available Apple M4 Mac mini.
These values are evidence for this machine and toolchain, not universal
performance thresholds.

The exact Release command used the checked-in `Package.resolved`, macOS arm64
destination, Release configuration, and the `RawCull` scheme exactly as
prescribed by the stabilization plan. It produced a development-signed build;
it is not distribution-signing evidence.

## Isolated model/backend contract matrix

After the four ordered gates, eight isolated suites ran together and passed
53 of 53 tests:

- `RawCullAIIntegrationTests`
- `RawCullAIModelDownloadsTests`
- `PhotoAIKitSimilarityMigrationTests`
- `TypedAIPersistenceMatrixTests`
- `RawCullSemanticSearchTests`
- `DeepAIReviewFeatureTests`
- `AICacheBoundaryTests`
- `ThumbnailCacheIdentityTests`

| Required state | Automated evidence | Status |
|---|---|---|
| No downloaded model | `Composition root reports the complete Phase 1 capability surface` proves Vision similarity fallback, explicit semantic unavailability, missing SAM 3, and available core storage; the core smoke suites remain green | Contract green |
| Valid DataComp CLIP | Typed DataComp artifacts relaunch, index, rank, and remain backend-specific; semantic CLIP services rank deterministically | Synthetic contract green; real bundle pending |
| Valid OpenAI CLIP | Typed OpenAI artifacts relaunch without DataComp cross-loading; model selection and semantic state remain explicit | Synthetic contract green; real bundle pending |
| Corrupt/incomplete CLIP | Model validation reports missing/corrupt state and recovers after restoration; invalid and non-finite CLIP payloads are isolated without data loss | Contract green; real corrupt-bundle exercise pending |
| Valid SAM 3 | Deep Review publishes typed progress, masks, completed results, and cancellation through an isolated segmenter | Synthetic contract green; real bundle pending |
| Corrupt/missing SAM 3 | Missing/corrupt resource capability and unavailable Deep Review are explicit; cancellation cannot leave an owned task running | Contract green; real corrupt-bundle exercise pending |
| Backend switch during work | Superseded semantic hydration and queries cannot publish over the replacement backend; similarity generations and Deep Review cancellation remain independent | Contract green |

No production model archive or binary is checked in. All three production
download descriptors remain release-blocked by their licence/provenance audit,
and the self-hosted manifest remains deliberately unconfigured. A read-only
inventory of the app's sandboxed live Models directory was also denied by
macOS privacy controls, so no live user model was inspected or mutated. The
table therefore distinguishes deterministic contract coverage from required
real-model execution.

## Compatibility and manual matrix

| Requirement | Evidence | Status |
|---|---|---|
| Upgrade fixtures | Vision, DataComp, OpenAI, mixed-backend, partial-index, legacy-burst migration, ratings/settings, saved files, and typed artifact fixtures passed in the full suite | Automated green |
| Cache independence | Independent clears preserve ratings, settings, decisions, model resources, and licence acceptance; thumbnail representation changes preserve Vision, CLIP, and SAM identities | Automated green |
| Same-path replacement | Synthetic source-byte replacement changes thumbnail/source identity and preserves only compatible AI records | Automated green; real RAW replacement pending |
| macOS 27 | All gates ran on macOS 27.0 build `26A5388g`, arm64 | One OS build only; minimum/latest matrix pending |
| Apple Silicon memory profiles | Cache policy tests cover simulated 16 GB low-, medium-, high-free-memory and warning-pressure states; gates ran on a 16 GB Apple M4 | Real 32/64 GB or other high-memory hardware pending |
| Model download and licence | Release blocking, verified text hashes, consent gating, changed-licence invalidation, progress, install, and removal pass with isolated services | Production resume/interruption and real licence flow pending |
| VoiceOver | Spoken-value helpers and keyboard actions pass in smoke/full | Hands-on signed-app checklist pending |
| Clean-account install and upgrade | No source or package gate failure | Signed clean-account install and 2.3.4-to-3.0 upgrade pending |

There are no real RAW fixtures in this repository. No production model was
downloaded, installed, removed, or given licence acceptance during this phase.
No live rating, culling decision, settings, saved-file, semantic, or subject-
mask store was modified.

## Release decision

The repeatable automated regression is green and the earlier TSan harness hang
does not reproduce after its committed fix. Release remains blocked on:

1. valid DataComp CLIP, OpenAI CLIP, and SAM 3 bundles plus corrupt/incomplete
   copies for the real backend matrix;
2. real RAW same-path replacement and fixed real-catalog contention captures;
3. minimum/latest macOS 27 and additional Apple Silicon memory classes;
4. production model-download resume/interruption and licence acceptance;
5. signed VoiceOver, clean-account install, and 2.3.4 upgrade sessions;
6. App Store Connect confirmation that provisional build 300 is unused; and
7. distribution signing, notarization, stapling, Gatekeeper, final artifact,
   hash reproduction, and exact release tag evidence.

Any persistent decision loss, backend confusion, stale async publication,
hang, or TSan report remains an unconditional release blocker.
