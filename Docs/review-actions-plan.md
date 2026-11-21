# Plan: Review actions 1–5 (CI, lint, Vision, history, coverage)

Status: draft · 2026-11-21 · branch `version-3.4.9` · steps 5–6 done (Vision phases 2–3), except the end-to-end burst run

## Why

A review of the codebase on 2026-11-21 scored RawCull about 6.9 / 10. The code itself scores well. The low scores come from what surrounds it:

| Area | Score | Main reason |
|---|---|---|
| Build, CI and release | 4.0 | No CI in the app repo or in the packages. Releases are manual. |
| Process and history | 4.5 | 440 commits in 30 days. 152 of them are titled "update". |
| Concurrency | 6.5 | The Vision hang is mitigated (phase 1), not fixed. (Fixed since: phases 2–3 are done.) |
| Testing | 7.5 | About 1,070 tests, but no coverage numbers. |
| Code quality | 7.5 | Clean code, but the SwiftLint rules are not enforced. |

This plan covers the five actions with the largest effect. Done together, they should bring the score to about 8.

## Baseline (measured 2026-11-21)

| Metric | Value | How measured |
|---|---|---|
| CI workflows | 0 in RawCull, PhotoAIKit, PhotoAnalysisKit, PhotoEvidenceKit, RawCullCore, RawParserKit | `ls .github/workflows` |
| SwiftLint (whole repo) | 304 errors, 2,584 warnings | `swiftlint lint --quiet` |
| SwiftLint errors by rule | `identifier_name` 281, `cyclomatic_complexity` 14, `large_tuple` 4, `file_length` 4, `function_parameter_count` 1 | same |
| SwiftLint errors by folder | `RawCullTests` 209, `RawCull` 63, `RawCullReleaseTests` 19, `Scripts` 11, `Tools` 2 | same |
| Top warnings | `multiline_arguments` 1,401, `line_length` 779, `identifier_name` 324, `cyclomatic_complexity` 54, `file_length` 47, `function_body_length` 43, `force_unwrapping` 39, `type_body_length` 30 | same |
| SwiftFormat | 157 of 506 files need formatting | `swiftformat --lint .` |
| Largest type bodies | `SimilarityScoringModel` about 1,050 lines; `DeepAIReviewFeature.swift` holds about 20 types in 1,039 lines | `wc -l`, the graph |
| Commits, last 30 days | 440, of which 152 "update" and 112 merges | `git log --since=2026-10-22` |
| Release tags | 46, latest `v3.4.5` | `git tag` |
| Code coverage | not collected (`RawCull.xctestplan` has no `codeCoverage` option; `test-smoke` passes `-enableCodeCoverage NO`) | test plans, Makefile |
| Vision worst case | 8 requests for 10 pool threads (10-core), 7 for 8 (8-core). Since phases 2–3: 1 request at a time, waiting callers suspend | [visionupdate.md](visionupdate.md#phase-1-result-2026-11-21) |

Things that shape the CI design:

- **Toolchain.** `MACOSX_DEPLOYMENT_TARGET = 27.0`, Xcode 27.2, Swift 6.2. GitHub's hosted macOS runners usually lag a new Xcode by weeks. Plan for a self-hosted runner on your own Mac, and switch to hosted runners if they catch up.
- **Package access.** All packages are pinned by HTTPS URL. (`PhotoEvidenceKit` used SSH until 2026-11-21; fixed.)
- **Signing.** The app uses app groups with a team prefix (`93M47F4H9T.no.blogspot.RawCull.mcp`). Find out whether the test host runs with `CODE_SIGNING_ALLOWED=NO`, or whether CI needs a development certificate.
- **Existing targets to reuse.** `test-smoke` (with the 424-test manifest check), `test-full` (Thread Sanitizer, serial), `test-scripts`, `test-mcp`, `verify-ai-import-boundary` and `verify-model-provenance`.

## The order

| Step | What | Size | Risk | Status |
|---|---|---|---|---|
| 1 | `make lint` and `make format-check` with a baseline | S | none | not started |
| 2 | CI for RawCull (pull requests: lint + smoke; nightly: full) | M | low | not started |
| 3 | CI for the five packages | S | none | not started |
| 4 | Vision hang regression test | S | low | not started |
| 5 | Vision phase 2 (PhotoAnalysisKit) | M | medium | done (PhotoAnalysisKit 1.4.0), see [visionupdate.md](visionupdate.md#phase-2-result-2026-11-21) |
| 6 | Vision phase 3 (PhotoAIKit and RawCull) | M | medium | done (PhotoAIKit 3.1.0) except the end-to-end burst run, see [visionupdate.md](visionupdate.md#phase-1-cap-removed-2026-11-21) |
| 7 | Pay down lint errors and split the two largest types | M | low | not started |
| 8 | Commit and release hygiene | XS | none | not started |
| 9 | Coverage collection and floors | S | none | not started |

Step 1 comes first because CI (step 2) needs a lint command that passes today. Step 4 should land before CI turns on parallel tests, so a return of the hang fails a run instead of stalling it. Steps 8 and 9 can be done at any time.

## Action 1: Add CI

### Step 2: RawCull

1. **Runner.** Register your Mac as a self-hosted GitHub Actions runner with the label `xcode-27`. Use a separate macOS user so CI cannot touch your own Keychain or `~/Downloads` catalog.
2. **Packages.** Done: every package uses an HTTPS URL, so the runner needs no SSH key.
3. **Workflow `.github/workflows/ci.yml`**, run on every pull request and every push to `main`:
   - `make lint` (step 1)
   - `make verify-ai-import-boundary`
   - `make verify-model-provenance`
   - `make test-scripts`
   - `make test-mcp`
   - `make test-smoke`
4. **Workflow `.github/workflows/nightly.yml`**, scheduled nightly and also startable by hand:
   - `make test-full` (Thread Sanitizer)
   - the `RawCull` test plan with parallel testing on, run 3 times in a row. This repeats the check from Vision phase 1 every night.
   - `make test-performance`. Store the results as an artifact so you can compare them over time.
5. **Kept out of CI:** the release, sharpness, combined-review and MCP-release targets. They need real models and real catalogs. They stay manual and part of `release-preflight`.
6. **Branch protection.** On `main`, require `ci.yml` to pass before merging.

Done when: a pull request with a deliberate lint error fails, and the same pull request without it passes. One nightly run is green.

### Step 3: Packages

Add a `ci.yml` to PhotoAIKit, PhotoAnalysisKit, PhotoEvidenceKit, RawCullCore and RawParserKit that runs `swift build` and `swift test` on the same runner. PhotoAnalysisKit also runs its tests with `--sanitize=thread`. A package release needs a green run on its tag.

Done when: each package shows a green run on `main`.

## Action 2: Enforce lint and format

### Step 1: Commands with a baseline (one PR)

1. Add Makefile targets:
   - `lint`: `swiftlint lint --strict --baseline .swiftlint-baseline.json`
   - `lint-baseline`: `swiftlint lint --write-baseline .swiftlint-baseline.json`
   - `format-check`: `swiftformat --lint .`
   - `format`: `swiftformat .`
2. Write the baseline from today's 304 errors and 2,584 warnings and commit it. From then on, only new violations fail.
3. Format: run `swiftformat .` once, on its own commit with no other changes, so the 157 files are fixed in one commit that is easy to skip. Then add the commit to `.git-blame-ignore-revs`. After that, `format-check` must pass.
4. Add `make lint` and `make format-check` to `ci.yml`.
5. Optional: an Xcode build phase that runs `swiftlint --baseline` only on changed files, so warnings show up in Xcode.

Done when: `make lint` and `make format-check` pass on a clean tree and fail on a new violation.

### Step 7: Pay down the baseline (one PR per bullet)

- **`identifier_name` (281 errors, 209 of them in tests).** Most are short names in tests. Either rename them, or set a looser `identifier_name` for `RawCullTests/` with a nested `.swiftlint.yml`. Choose one way and use it everywhere.
- **`force_unwrapping` (39).** Fix the ones in app code first: `CombinedReviewResponse.swift` (6) and `ReviewImageSource.swift` (4). The ones in tests and scripts can stay in the baseline.
- **Split `DeepAIReviewFeature.swift`.** Move `RawCullDeepReviewImageDecoder`, `DeepAIReviewRenderMaskStore` and `RawCullDeepAIReviewPipeline` into their own files next to it. Move the value types (preset, reason, candidate, result, state) into `DeepAIReviewModels.swift`. Only files move; nothing else changes.
- **Split `SimilarityScoringModel`.** Split the 1,050-line class along what it does: indexing, distance computation and presentation state. Use `SimilarityScoringModel+Indexing.swift` and similar files, or helper types where the state really is separate. Run `RawCullSimilarityFeatureTests` and `PhotoAIKitSimilarityMigrationTests` before and after.
- After each PR, run `make lint-baseline` again so the baseline only shrinks. Track the error count in this document.

Done when: errors in `RawCull/` are 0, and no app type body is over 600 lines.

## Action 3: Finish the Vision fix

### Step 4: Guard against a regression (app only, one PR)

Phases 2–3 shipped without this test. It now guards the fix, not the phase 1 mitigation.

1. Add `VisionConcurrencyRegressionTests` to `RawCullTests`. It starts `activeProcessorCount × 3` concurrent feature prints through the shared `VisionFeaturePrintBackend` from `RawCullAIModelRuntime`, and the same number of `SharpnessScoringModel` scorings on small fixture images, all at once. Give it `.timeLimit(.minutes(1))`. The PhotoAIKit 3.1.0 test (3 × cores feature prints in one minute) covers the package alone; this one covers the app, where both packages share `VisionRequestGate.shared`.
2. Marking the Vision suites `.serialized` is no longer needed: every Vision request now goes through the gate, so parallel test runs cannot exhaust the pool. Leave the suites as they are.
3. Optional: time similarity indexing on a 500-image catalog, as [visionupdate.md](visionupdate.md#phase-1-result-2026-11-21) asks. The 275-photo real-catalog check already showed 1.0 s alone and 1.8 s next to sharpness scoring.

Done when: the new test passes 3 runs in a row in the nightly job.

### Steps 5–6: Phases 2 and 3 (done)

Done on 2026-11-21, see [visionupdate.md](visionupdate.md):

- PhotoAnalysisKit 1.4.0 and PhotoAIKit 3.1.0 are released and pinned. Every Vision request in the app goes through `VisionRequestGate.shared`.
- The `RawCull` test plan ran three times in a row with no failures, the release sharpness test passed, and sharpness scoring plus similarity indexing at 10 tasks on a 10-core Mac finished.
- The phase 1 cap on sharpness scoring is removed.
- `FocusMaskEngine.runCancellableWorker` is recorded as the next issue of the same kind, under Risks in visionupdate.md.

Still open: the end-to-end burst analysis through the app (`Scripts/PrepareBursts.py` over MCP), which needs a build of this branch installed as the app. The step 4 regression test does not exist yet.

## Action 4: Commit and release hygiene (step 8)

1. **Commit messages.** Use the imperative, and say what changed and in which area. For example: "Cap sharpness scoring at half the cores (Vision plan phase 1, step 3)". Recent plan commits already do this. Stop using "update" and "updates". A `commit-msg` hook in `Scripts/hooks/` can reject those two words alone; install it with `make install-hooks`.
2. **Merging.** Squash-merge feature and plan branches into `main`, one commit per plan step. That cuts the 112 merge commits and makes `git bisect` usable.
3. **Tags.** Tag every TestFlight and App Store build as `vX.Y.Z`. Today the latest tag is `v3.4.5`, while the branch is 3.4.9. `release-preflight` already checks the tag. Also make it fail when the tag is missing.
4. **Changelog.** Keep `CHANGELOG.md` with one section per tagged version. Write it from the squashed commit titles.
5. Add these rules to [contributing.md](contributing.md).

Done when: `main` history since the change has no "update" commits, and every shipped build has a tag and a changelog entry.

## Action 5: Measure coverage (step 9)

1. Turn on code coverage in `RawCull.xctestplan` and set the targets to `RawCull`. Keep `test-smoke` without coverage so it stays fast. Collect coverage in the nightly run.
2. Add `Scripts/CoverageReport.py`. It runs `xcrun xccov view --report --json` on the result bundle and prints line coverage per top-level folder: `Intelligence/`, `Main/`, `Model/`, `Actors/`, `Views/`. Add a `Test*.py` for it, like the other scripts.
3. Measure for one week, then set minimums 2 points below what you measured, for `Intelligence/`, `Main/` (the MCP controller) and `Model/`. The nightly job fails if coverage drops below a minimum. `Views/` gets no minimum.
4. Packages: run `swift test --enable-code-coverage` in package CI and print the total. No minimum at first.
5. Write the first numbers into this document.

Done when: the nightly job publishes coverage per folder and enforces the three minimums.

## Risks

- **Hosted runners lag behind Xcode 27.** A self-hosted runner needs your Mac to be on. Accept that nightly runs are skipped while it is off.
- **Self-hosted runner security.** Run it only for your own repositories and branches. Do not run pull requests from forks on it.
- **One big formatting commit.** It touches 157 files. Do it when no other branch is open, so nothing conflicts.
- **The baseline can hide old debt.** Step 7 exists for that. Track the error count, or the baseline will never shrink.
- **Vision tests are timing-sensitive.** A regression test with a 1-minute limit can fail on a loaded runner without a real hang. If it does, capture a `sample` before raising the limit.

## Not in scope

- Actions 6–9 from the review: the product decision on overlapping review features, the shared MCP IPC module (refactoring step 17), an architecture overview and a dependency audit.
- Notarization and App Store upload in CI. These stay manual, because they need signing secrets.
