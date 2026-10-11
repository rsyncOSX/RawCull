# Opt-in full six-ARW regression runner

Run from the repository with the installed local models:

```sh
python3 Scripts/RunCombinedReviewSix.py
```

Default inputs are the first six ARW files in `~/Downloads`, sorted by filename
(case-sensitive lexical order, not creation date). `.ARW` and `.arw` are accepted;
subdirectories and other file types are ignored. At least six files are required.
The runner prints the chosen filenames and saves their SHA-256 hashes beside the
run evidence in `evidence.inputs.json`. It passes those exact names to the Swift
test, so later directory additions cannot change that run's selection.

For a new set, preferably use a dedicated folder:

```sh
python3 Scripts/RunCombinedReviewSix.py --directory /path/to/new-set
```

Keep the original repeatable regression with:

```sh
python3 Scripts/RunCombinedReviewSix.py --frozen
```

`--frozen` selects the six original names and requires their recorded SHA-256 hashes.
Models are under
`~/ModelAssets/Release/Models`: `Qwen/qwen3_vl_2b`, `SAM3`, and `CLIP-DataComp`.
No assets are downloaded by the test. Xcode may need to resolve the project's
pinned Swift dependencies. An existing cache can be supplied with
`--packages /path/to/SourcePackages`. Use `--directory`, `--models` and `--output`
to override locations; the output directory must be new. `--preflight-only`
checks the selected files and model directory presence without building; frozen hashes
are enforced only with `--frozen`.
Model usability is checked during the integration test.

The runner invokes only the opt-in six-file Swift Testing method in
`RawCullTests/CombinedReviewRealModelTests.swift`. It uses the actual
`CombinedReviewFeature` and live Qwen, SAM3 and CLIP backends, Standard depth,
high-quality preview, the existing four-criterion goal, retained inputs and bounded
rejected-response retention. It runs all six images and the selection comparison,
not just the existing Qwen-only smoke path. RAWs are read only. Appearance and
technical source policies remain the production policies; this is not a forced
full-resolution RAW decode or a performance benchmark.

No production Swift source, settings, installed app, normal review store or model
assets are edited. Xcode builds a separate Debug RawCull app as the test host;
this is an app-hosted integration test, not a hostless command-line implementation.
ReviewArtifactStore uses only the unique output directory. The runner writes build
products under `/private/tmp/RawCull-evaluation-build`, plus its log and xcresult
beside the evidence directory. Run one instance at a time because the build cache
and heavyweight model resources are shared.

## Fixed engineering acceptance

The checks require:

- Six terminal image results, with every scheduled stage completed successfully.
- Category attempts within immutable run caps.
- An overview and CLIP evidence for each image. Current-semantic measurements and
  a fully retained registered subject crop are required when subjects are found.
  Frozen mode additionally requires subjects in every original wildlife image.
- Finite available measurements with current mask/scorer semantics.
- An accepted report for each image covering composition, exposure, visibility
  and detail through claim categories.
- A six-cell selection report. Frozen mode requires abstention and no preferred
  image for the original unrelated set; new comparable sets may select a winner.

Checks run after diagnostic persistence, so inference/validation failures retain
their evidence. A prerequisite/runtime/build failure can stop earlier; the runner
rejects a zero-exit run without `diagnostic.json`. Missing models/files fail before inference; changed frozen RAW hashes also fail. Models and pipeline identities are saved in the
run snapshot; model weights are not frozen by this input hash file.

The retained store includes manifests, accepted stage payloads, exact request PNGs
and bounded rejected-response envelopes. `diagnostic.json` additionally contains
recorded prompts/responses from this test backend, including accepted responses;
these private diagnostics are not committed. Failed reports remain failed even
when an unsynthesized summary is available. No known-issue suppression or automatic
weakening of checks is used.

## Iteration and photographic acceptance

One invocation performs one run and exits nonzero on failure. It does not change
app code, automatically retry until a lucky generation passes, or adjust acceptance
criteria. After a reviewed implementation change, invoke it again; each default
run retains separate evidence. This preserves the user's request to keep the test
independent of production-code adjustments.

Engineering pass is necessary but insufficient for photographic acceptance.
Correct mask/crop anatomy, foreground/rear sparrow differentiation, clipping,
overlap, behavior and factual prose still require reviewed source-space reference
annotations and inspection of retained inputs. Category coverage checks do not
prove that each sentence is useful or true. This runner does not claim original
phase 6 resource qualification or phase 7 independent photographic qualification.
The current `combined-v7` export fails several of these checks; that is expected
regression evidence, not an expected-pass/known-issue exemption.

## Initial verification — 11 October 2026

The original fixed-input integration test compiled and ran all six ARWs with Qwen, SAM3 and CLIP.
It finished with 59 terminal work items: 50 completed and 9 failed. The test
correctly exited nonzero rather than accepting these partial results. Five overview
requests failed (four contextual-concept grounding checks, one uncertainty-length
check); the rabbit reconciliation/report failed observation support; swan and
sparrow reports failed registered-focus support. Three report work items completed,
each with one claim and incomplete criterion coverage. Failed synthesis may expose
an empty report placeholder in the feature result; report work state remains the
authoritative acceptance status. All six comparison cells survived and selection
abstained. Eight rabbit-image measurements, eight crop observations and fourteen
CLIP stages completed. This reproduces the updated export's broad failure pattern.

Private evidence: `/private/tmp/rawcull-six-ra2k6bn7/evidence/`.
Xcode result: `/private/tmp/rawcull-six-ra2k6bn7/evidence.xcresult`.
The directory includes retained stage inputs, bounded rejected responses and
`diagnostic.json`. No photographs or generated responses were added to Git.

`PYTHONDONTWRITEBYTECODE=1 python3 Scripts/TestRunCombinedReviewSix.py`: three
orchestration checks passed, covering missing executed-test evidence, successful
execution evidence and preservation of failing exit status. Frozen-RAW preflight
and `git diff --check` passed. No production-code fixes were made to obtain a pass.

Selection update verification: five runner checks pass, including filename ordering,
case-insensitive ARW extension filtering, ignoring subdirectories, freezing the
original names, rejecting fewer than six files before Xcode, and passing the exact
selected names to the test process. Both normal and frozen local preflights pass.
The revised Swift suite compiled and passed with all three inference tests explicitly
disabled, confirming opt-in behavior. The new selection mode was not followed by
another full inference run; the initial full-run evidence above remains unchanged.
