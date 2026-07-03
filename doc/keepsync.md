# Keeping RawCull and RawCullSAM3 in Sync

## Purpose

RawCull is the canonical repository for the upcoming issue-closing work documented in `doc/issues.md`. Fix shared, non-AI issues in RawCull first, then port the same fix to RawCullSAM3, which will later be renamed RawCullAI.

The goal is not to make the repositories identical. RawCullSAM3 has additional AI behavior that must be preserved. The goal is to make shared fixes repeatable, traceable, and hard to lose silently while both apps continue to evolve.

The default workflow is a patch queue:

1. Fix one issue in RawCull.
2. Test and commit the RawCull fix.
3. Export the fix as a patch file.
4. Apply the patch to RawCullSAM3.
5. Resolve only the differences required by SAM3-specific code.
6. Test and commit the SAM3 port.

This gives every issue a visible chain: issue number, RawCull commit, patch file, RawCullSAM3 commit, and any SAM3-specific adjustment notes.

## Current Repo Relationship

The two app repositories are siblings:

- RawCull: `/Users/thomas/GitHub/RawCull/RawCull`
- RawCullSAM3: `/Users/thomas/GitHub/RawCull/RawCullSAM3`

Many Swift files still share the same relative path below the app source folder. That makes patch-based sync practical for many fixes. The root app source folders are different, however:

- RawCull app sources live below `RawCull/`.
- RawCullSAM3 app sources live below `RawCullSAM3/`.

A repo-root patch from RawCull will usually contain paths such as `RawCull/Actors/ScanFiles.swift`. The equivalent file in RawCullSAM3 is `RawCullSAM3/Actors/ScanFiles.swift`, so that patch will not apply cleanly from the SAM3 repo root without path rewriting.

RawCullSAM3 also adds AI-specific systems, including CoreAI, CLIP, SAM, subject segmentation, mask caches, AI settings, and additional focus/saliency state. Some files have also been split or moved in RawCullSAM3. Those areas may need a manual port even when the RawCull patch is correct.

The practical rule is:

- Shared file, same relative path below the app source folder: try the same patch first.
- Shared behavior but moved/split in SAM3: use the RawCull patch as the intent document and port manually.
- SAM3-only AI behavior: preserve it unless the issue explicitly targets SAM3.

## Recommended Workflow

Fix one documented issue at a time unless several issues are tightly coupled and touch the same files. Small issue commits make patches easier to review, apply, and recover from.

For each issue:

1. Start with clean worktrees in both repositories.
2. Create a RawCull issue branch.
3. Implement the fix in RawCull only.
4. Add or update focused tests when the risk justifies it.
5. Run focused tests and `make test-smoke` when practical.
6. Commit the RawCull fix.
7. Export one or more patch files from path-compatible subdirectories.
8. Check the patch against RawCullSAM3 with `git apply --3way --check`.
9. Apply the patch if the check succeeds.
10. If the check fails, manually port the same intent while preserving SAM3-only behavior.
11. Run equivalent SAM3 tests.
12. Commit the RawCullSAM3 port with a reference to the RawCull commit and patch file.
13. Update issue documentation only after both repos are handled, unless the issue is RawCull-only.

Do not treat a patch conflict as a failure. Treat it as information: either the repositories have drifted in that area, or RawCullSAM3 has intentional AI-specific structure that needs a local adaptation.

## Patch Generation Strategy

Generate patches from the deepest common path that is equivalent between the two repositories. This avoids the top-folder mismatch.

### App Source Patches

Generate app-source patches from inside:

```bash
cd /Users/thomas/GitHub/RawCull/RawCull/RawCull
```

Apply them from inside:

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3/RawCullSAM3
```

This turns a changed file such as:

```text
/Users/thomas/GitHub/RawCull/RawCull/RawCull/Actors/ScanFiles.swift
```

into a patch path like:

```text
Actors/ScanFiles.swift
```

That same relative path can then apply inside `RawCullSAM3/RawCullSAM3`.

### Test Patches

Generate test patches from inside:

```bash
cd /Users/thomas/GitHub/RawCull/RawCull/RawCullTests
```

Apply them from inside:

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3/RawCullSAM3Tests
```

This works only when the test files share equivalent names and structure. If SAM3 has different tests for the same behavior, port the test intent manually.

### Repo-Root Patches

Handle repo-root files separately. Examples include:

- `Makefile`
- `.xcodeproj` files
- `.xctestplan` files
- entitlements
- app icons and assets
- repo-level docs

Root-level patches often contain repository-specific paths, target names, bundle identifiers, or Xcode project references. Review these manually instead of assuming a RawCull root patch should apply to RawCullSAM3.

### Patch Names

Store patch files with issue-oriented names. Recommended examples:

```text
patches/issue-007-catalog-state-app.patch
patches/issue-007-catalog-state-tests.patch
patches/issue-007-catalog-state-sam3-adjustment.patch
```

If patches are kept in the repo, commit them only when they are useful as durable project artifacts. Otherwise, the git commits are the authoritative history and patch files can be treated as temporary transfer artifacts.

## Commands

### Check Both Worktrees

```bash
cd /Users/thomas/GitHub/RawCull/RawCull
git status --short --branch

cd /Users/thomas/GitHub/RawCull/RawCullSAM3
git status --short --branch
```

Both should be clean before starting a port. If either repo has unrelated changes, do not overwrite them. Finish, commit, stash, or explicitly account for them first.

### Create a RawCull Issue Branch

```bash
cd /Users/thomas/GitHub/RawCull/RawCull
git switch -c codex/issue-007-catalog-state
```

Use a short branch name that includes the issue number and subsystem.

### Commit the RawCull Fix

```bash
cd /Users/thomas/GitHub/RawCull/RawCull
git status --short
make test-smoke
git add RawCull RawCullTests doc/issues.md
git commit -m "Fix issue 7: clear stale catalog state"
```

Adjust the staged paths to the actual files changed. Do not stage unrelated work.

### Export an App Source Patch

After committing the RawCull fix, export the app-source portion from inside the RawCull app source folder:

```bash
mkdir -p /Users/thomas/GitHub/RawCull/RawCull/patches

cd /Users/thomas/GitHub/RawCull/RawCull/RawCull
git diff HEAD~1 HEAD -- . > ../patches/issue-007-catalog-state-app.patch
```

The resulting patch uses paths relative to `RawCull/`, such as `Model/ViewModels/RawCullViewModel+Catalog.swift`.

If the fix also touched tests, export a separate test patch:

```bash
cd /Users/thomas/GitHub/RawCull/RawCull/RawCullTests
git diff HEAD~1 HEAD -- . > ../patches/issue-007-catalog-state-tests.patch
```

### Check the Patch Against RawCullSAM3

Check before applying:

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3/RawCullSAM3
git apply --3way --check /Users/thomas/GitHub/RawCull/RawCull/patches/issue-007-catalog-state-app.patch
```

If there is a test patch:

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3/RawCullSAM3Tests
git apply --3way --check /Users/thomas/GitHub/RawCull/RawCull/patches/issue-007-catalog-state-tests.patch
```

### Apply the Patch

If the check succeeds:

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3/RawCullSAM3
git apply --3way /Users/thomas/GitHub/RawCull/RawCull/patches/issue-007-catalog-state-app.patch
```

Apply the test patch from the SAM3 test folder if needed:

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3/RawCullSAM3Tests
git apply --3way /Users/thomas/GitHub/RawCull/RawCull/patches/issue-007-catalog-state-tests.patch
```

### Handle a Failed Patch Check

If `git apply --3way --check` fails:

1. Read the RawCull commit and patch.
2. Identify whether SAM3 moved, split, or extended the affected code.
3. Re-implement the same behavior in the SAM3 structure.
4. Preserve SAM3-only AI behavior unless it is directly involved in the bug.
5. Record the adjustment in the SAM3 commit body.

Useful inspection commands:

```bash
cd /Users/thomas/GitHub/RawCull/RawCull
git show --stat HEAD
git show HEAD

cd /Users/thomas/GitHub/RawCull/RawCullSAM3
git status --short
```

### Commit the RawCullSAM3 Port

```bash
cd /Users/thomas/GitHub/RawCull/RawCullSAM3
make test-smoke
git status --short
git add RawCullSAM3 RawCullSAM3Tests
git commit -m "Port RawCull issue 7: clear stale catalog state"
```

Use the commit body to record traceability:

```text
RawCull commit: <hash>
Patch: patches/issue-007-catalog-state-app.patch
Applied cleanly: yes
SAM3 adjustments: none
```

If the patch required manual work:

```text
RawCull commit: <hash>
Patch: patches/issue-007-catalog-state-app.patch
Applied cleanly: no
SAM3 adjustments: ported catalog clearing around AI-specific focus/saliency state without removing subject segmentation state.
```

## Per-Issue Checklist

Use this checklist for every issue port.

```text
[ ] RawCull worktree clean.
[ ] RawCullSAM3 worktree clean.
[ ] Issue selected from doc/issues.md.
[ ] RawCull issue branch created.
[ ] Fix implemented in RawCull.
[ ] Focused tests added or updated if needed.
[ ] Focused tests run in RawCull.
[ ] make test-smoke run in RawCull when practical.
[ ] RawCull commit created.
[ ] App patch exported if app source changed.
[ ] Test patch exported if tests changed.
[ ] Repo-root changes reviewed separately if needed.
[ ] Patch checked against RawCullSAM3 with git apply --3way --check.
[ ] Patch applied cleanly or manually ported.
[ ] SAM3-only AI behavior preserved.
[ ] Focused SAM3 tests run.
[ ] make test-smoke run in SAM3 when practical.
[ ] RawCullSAM3 commit references RawCull commit hash and patch filename.
[ ] doc/issues.md updated only after both repos are handled, unless the issue is RawCull-only.
```

## Conflict Policy

Prefer preserving RawCullSAM3 AI behavior. A shared RawCull fix should not remove or flatten SAM3-only code unless the issue explicitly requires changing that AI behavior.

When a patch conflicts:

- First decide whether the conflict is accidental drift or intentional SAM3 structure.
- If it is accidental drift, bring SAM3 back toward RawCull where appropriate.
- If it is intentional AI-specific structure, port the fix into the SAM3 shape.
- If the same file repeatedly conflicts, document why in the SAM3 commit body or a local sync note.
- If the same logic repeatedly requires dual edits, consider moving the pure shared part into `RawCullCore`.

Do not resolve conflicts by blindly choosing RawCull or SAM3 wholesale. The correct result is usually RawCull's bug fix plus SAM3's AI-specific extension points.

## When To Use RawCullCore

`RawCullCore` is useful when repeated dual maintenance proves that logic is truly shared, pure, and worth the package boundary.

Good candidates:

- Pure models.
- Parser helpers.
- Ranking and grouping logic.
- Histogram or statistics helpers.
- Cache-key or file-identity helpers.
- Deterministic validation functions.

Poor candidates:

- SwiftUI views.
- App scene setup.
- AppKit-heavy UI code.
- CoreImage, Vision, or Metal pipelines unless carefully isolated and genuinely shared.
- Rsync process integration.
- Security-scoped bookmark lifecycle.
- SAM, CLIP, or CoreAI-specific behavior.

Use extraction only after it reduces real repeated work. A patch conflict once is not enough reason to move code into a package. Repeated conflicts in the same pure logic are a stronger signal.

## Testing Policy

Run focused tests for each fix. The focused test should cover the behavior changed by the issue, not just the file touched by the patch.

Use `make test-smoke` as the default per-issue confidence check when practical. It is the right balance for keeping both repositories moving while still catching broad regressions.

Use `make test-full` for higher-risk areas:

- Swift concurrency changes.
- Cache actors.
- Catalog switching.
- Thumbnail loading or preloading.
- Copy and rsync behavior.
- Sharpness scoring.
- Security-scoped access.
- Any fix where stale async results, cancellation, or actor isolation are part of the bug.

For RawCullSAM3, run equivalent tests and also watch for regressions around:

- Subject masks.
- SAM mask cache behavior.
- CLIP or CoreAI model loading.
- Saliency/focus evidence.
- AI-specific settings and progress UI.

If the SAM3 port is manual, tests matter more because the patch no longer proves textual equivalence.

## Commit Message Policy

RawCull commit format:

```text
Fix issue N: short description
```

Example:

```text
Fix issue 7: clear stale catalog state
```

RawCullSAM3 commit format:

```text
Port RawCull issue N: short description
```

Example:

```text
Port RawCull issue 7: clear stale catalog state
```

The RawCullSAM3 commit body should include:

```text
RawCull commit: <hash>
Patch: <patch path>
Applied cleanly: yes/no
SAM3 adjustments: <none or short explanation>
```

This makes it possible to audit which fixes have crossed over and which required local adaptation.

## Recommended Default

Use a patch queue per issue as the default workflow.

Use batches only when issues are tightly coupled and touch the same files. Batches reduce repeated test runs, but they also make conflicts harder to understand. If a batch fails to apply to SAM3, split it back into issue-level patches.

Move logic to `RawCullCore` only after repeated friction proves the extraction is worth it. The package boundary is valuable for pure shared logic, but it is not a substitute for disciplined per-issue commits.

The best routine is:

```text
RawCull issue fix -> RawCull tests -> RawCull commit -> patch -> SAM3 check/apply -> SAM3 tests -> SAM3 commit
```

That rhythm keeps both apps close without pretending they are the same product.

## Assumptions

- RawCull remains the canonical source for shared, non-AI fixes.
- RawCullSAM3 keeps its AI-specific behavior even when a RawCull patch touches nearby code.
- Patch files are portable transfer artifacts, while git commits remain the authoritative history.
- Root-level project files require manual review because target names, paths, and project metadata may differ.
- Issue documentation should not be marked fully closed until both repositories are handled, unless the issue explicitly applies only to RawCull.
