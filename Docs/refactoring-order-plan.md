# Plan: Refactoring order

Status: draft · 2026-11-20 · branch `version-3.4.8`

The order in which to carry out the two plans:

- **VM plan:** [viewmodel-decomposition-plan.md](viewmodel-decomposition-plan.md), breaking up `RawCullViewModel` (finding 1)
- **QF plan:** [code-quality-followups-plan.md](code-quality-followups-plan.md), the follow-ups for findings 2–6

## Prompt to start each step

Copy this into a new Claude Code session in `/Users/thomas/GitHub/RawCull/RawCull`. Replace `<N>` with the step number from the table below.

```text
We are refactoring RawCull following three plans in Docs/:
  - Docs/refactoring-order-plan.md          (the order; this is the master plan)
  - Docs/viewmodel-decomposition-plan.md    ("VM plan")
  - Docs/code-quality-followups-plan.md     ("QF plan")

Do step all steps of Docs/refactoring-order-plan.md. 

1. Read the master plan's row and section for steps , then read every section
   of the VM plan and the QF plan it links to, including the VM plan's
   "Rules for every slice" if the step is a slice.
2. Use the graphify graph in graphify-out/ before touching code:
   - Run /graphify query for the types and members this step moves or changes,
     e.g. /graphify query "what reads or writes RawCullViewModel.zoomOverlayVisible"
     and /graphify explain "<TypeName>" for each type involved.
   - Use /graphify path "<A>" "<B>" to find hidden couplings between the code
     being moved and the rest of the app.
   - The graph can be stale or have INFERRED edges: confirm every consumer it
     reports with grep before relying on it, and grep for consumers it might
     have missed.
   - From the graph and grep, list every file you will change before editing.
3. Commit changes after each update.
4. Make the change in the small commits the plan describes. Change no behaviour.
   Build and run the RawCullTests test plan after each commit; every test must
   pass before the next commit.
5. When the step is done:
   - Rebuild the graph so the numbers are comparable to the baseline:
       $(cat graphify-out/.graphify_python) graphify-out/rebuild.py
   - Compare against the "Baseline" table in Docs/refactoring-order-plan.md
     and report the change for the metrics this step affects.
   - Update the step's "Status" in Docs/refactoring-order-plan.md and fill in
     its "Result" line with the measured numbers.
6. Stop and summarise: files changed, tests run and their result, graph
   numbers before and after, anything the plan got wrong. Do not start the
   next step, and do not push or open a PR unless I ask.
```

## Baseline (measured 2026-11-20)

| Metric | How to measure | Baseline |
|---|---|---|
| `RawCullViewModel` graph edges | `GRAPH_REPORT.md` → God Nodes | 399 |
| Main View Model community cohesion | `GRAPH_REPORT.md` → Community 0 | 0.02 |
| Stored properties on `RawCullViewModel` | count in `RawCullViewModel.swift` | 103 |
| App files referencing `RawCullViewModel` | `grep -rl RawCullViewModel RawCull --include='*.swift' \| wc -l` | 73 |
| `MCPAnalysisController.swift` lines | `wc -l` | 1,262 |
| `AnalysisJobStore.swift` lines | `wc -l` | 1,391 |
| `try?` in app + MCP sources | `grep -rn 'try?' RawCull Tools/RawCullMCP/Sources --include='*.swift' \| wc -l` | 157 |
| Import cycles | `GRAPH_REPORT.md` | none (must stay none) |

## The order

One step = one branch = one PR, commit all changes the current branch before the next step starts. The exception is the parallel track in phase 3, explained there.

| Step | What | Reference | Size | Risk | Status |
|---|---|---|---|---|---|
| 1 | Fix the `try?` uses that hide failures | QF → [Finding 5](code-quality-followups-plan.md#finding-5-fix-the-try-uses-that-hide-failures) | S | low | done |
| 2 | Move the subject-mask types out of `DeepReview/` | QF → [4.1](code-quality-followups-plan.md#41-code-fix-shared-primitives-in-the-wrong-place-s) | XS | none | done |
| 3 | Remove dead view-model state | VM → [Slice 0](viewmodel-decomposition-plan.md#slice-0-remove-dead-state-about-30-min) | XS | none | done |
| 4 | `ZoomOverlayModel` | VM → [Slice 1](viewmodel-decomposition-plan.md#slice-1-zoomoverlaymodel-low-risk-about-11-files) | S | low | done |
| 5 | Loupe viewport into `LoupeSessionModel` | VM → [Slice 2](viewmodel-decomposition-plan.md#slice-2-loupe-viewport-into-loupesessionmodel-low-risk-3-files) | XS | low | done |
| 6 | `WorkspacePresentationModel` | VM → [Slice 3](viewmodel-decomposition-plan.md#slice-3-workspacepresentationmodel-low-risk-many-small-consumers) | S | low | done |
| 7 | Make the MCP controller testable | QF → [Finding 3](code-quality-followups-plan.md#finding-3-make-the-mcp-controllers-state-explicit), step 3.1 | S | low | todo |
| 8 | Characterization tests for MCP transitions | QF → Finding 3, step 3.2 | M | low | todo |
| 9 | `FileOperationsModel` | VM → [Slice 4](viewmodel-decomposition-plan.md#slice-4-fileoperationsmodel-medium-risk) | M | medium | todo |
| 10 | Explicit MCP state (`Activity` / `Lifecycle` enums) | QF → Finding 3, step 3.3 | M | medium | todo |
| 11 | `RatingsModel` | VM → [Slice 5](viewmodel-decomposition-plan.md#slice-5-ratingsmodel-medium-risk-the-hot-path) | M | medium | todo |
| 12 | Typed MCP stop reasons + split the MCP files | QF → Finding 3, steps 3.4–3.5 | S | low | todo |
| 13 | `SelectionModel` | VM → [Slice 6](viewmodel-decomposition-plan.md#slice-6-catalogworkspace--selectionmodel-high-risk-the-most-read-state) (first PR) | M | high | todo |
| 14 | `CatalogWorkspace` | VM → Slice 6 (second PR) | L | high | todo |
| 15 | `BurstWorkflowController` | VM → [Slice 7](viewmodel-decomposition-plan.md#slice-7-burstworkflowcontroller-high-risk-the-biggest-win) | L | high | todo |
| 16 | Shrink the root and verify against targets | VM → [Slice 8](viewmodel-decomposition-plan.md#slice-8-shrink-the-root-and-verify) | S | low | todo |
| 17 | *Optional:* shared MCP IPC module | QF → Finding 3, step 3.6 | M | low | todo |
| 18 | *Optional:* `CombinedReview/` subfolders | QF → [4.2](code-quality-followups-plan.md#42-optional-tidy-combinedreview-subfolders-xs) | XS | none | todo |
| — | Decide: does Deep AI Review fold into Combined Review? | QF → [4.3](code-quality-followups-plan.md#43-product-decision-yours-not-a-refactor) | decision | — | open |
| — | Check identity-only `==` on `RawCullFileItem` | QF → [Finding 2](code-quality-followups-plan.md#finding-2-rawcullfileitem-no-refactor-one-check) | XS | — | open |
| — | Process habits | QF → [Finding 6](code-quality-followups-plan.md#finding-6-change-rate-process-only) | ongoing | — | open |

## Phases and why this order

### Phase 1: Quick fixes (steps 1–2)

- **Step 1 goes first** because it's the only item that fixes a real bug: two cache keys that collapse to one value if encoding fails. It's small, and nothing depends on it. Follow the QF plan's *Fix list* and add the SwiftLint rule it describes.
- **Step 2** only moves files. Doing it now means the Combined Review and Deep Review code is in its final place before anyone else touches those folders.

*Done when:* all 8 rows of the QF fix list are handled, there's a test proving a NaN no longer produces a shared key, and `DeepReview/` no longer holds anything Combined Review imports.

Result: done 2026-11-20. All 8 fix-list rows handled; `CacheKeyEncodingFailureTests` proves a NaN never yields a shared key; SwiftLint rule `try_optional_empty_data_fallback` added; policy in [contributing.md](contributing.md). `try?` 157 → 148. Subject-mask primitives now in `Intelligence/SubjectMasks/`. Plan corrections: the clear buttons (row 5) live in `CombinedReviewView`, not `CacheSettingsTab`.

### Phase 2: Low-risk view-model slices (steps 3–6)

Each one follows the VM plan's [Rules for every slice](viewmodel-decomposition-plan.md#rules-for-every-slice): create the model, add forwarders, move call sites, delete forwarders.

- These slices have few consumers and almost no coupling, so they're the place to settle the pattern (environment injection, revision counters, `resetForCatalogChange()`) before the harder slices.
- Together they take about 30 stored properties off `RawCullViewModel`.

*Done when:* stored properties are ≤ 75, no forwarders are left for slices 0–3, and the graph edges on `RawCullViewModel` have dropped visibly. Record the number.

Result: done 2026-11-20. 28 stored properties removed (counted as non-computed `var`/`let` in the class body: 91 → 63; the baseline's 103 used a different count, which would give about 75). No forwarders left. Graph edges 399 → 385, Main VM cohesion 0.02 → 0.03, no import cycles. Files referencing the root unchanged at 73, because views still reach slices through `viewModel.<slice>`; environment injection is slice 8. Plan correction: the loupe viewport went to a new root-owned `LoupeViewportModel`, not `LoupeSessionModel`, because that model is `@State` of `LoupeMainImageView` and would reset the zoom on every view-mode switch.

### Phase 3: MCP and the medium slices, alternating (steps 7–12)

- **Tests come first (steps 7–8).** The MCP controller has no transition tests today, so add them before step 10 changes its state.
- **Why alternate:** the MCP steps touch `RawCull/Main/MCPAnalysisController.swift` and `Tools/RawCullMCP/`. Slices 4–5 touch the view model, `Views/` and `Model/`. They don't overlap, so they can be developed in parallel sessions if you want. **Merge them in table order** anyway.
- **One caution:** slice 5 (`RatingsModel`) changes how `gridContentRevision` gets bumped. Run the grid projection tests (`CullingGridProjectionTests`, `CullingGridCoordinatorTests`) and check `gridProjectionBuildCount` explicitly.

*Done when:* `MCPAnalysisController` has no loose optional activity fields left, the MCP transition tests pass, ratings live in `RatingsModel`, and the `ImageReviewRating*` conformances have moved there.

Result: —

### Phase 4: High-risk view-model slices (steps 13–16)

- **They go last on purpose.** `SelectionModel`, `CatalogWorkspace` and `BurstWorkflowController` move the state that `MCPAnalysisWorkspace` reads. The MCP tests from phase 3 are the safety net, so they have to exist first.
- **Step 13 before 14:** selection is smaller and is needed by more of the narrow protocols.
- **Step 15 depends on 11, 13 and 14:** the burst workflow takes ratings, selection and the catalog as `init` dependencies.
- After each step in this phase, smoke-test every main view mode by hand: loupe, grid, similarity grid, rated grid, comparison grid, AI analysis, combined review. Also run one MCP job end to end.

*Done when:* the targets in the VM plan's [Goal and non-goals](viewmodel-decomposition-plan.md#goal-and-non-goals) are met: ≤ 20 stored properties, ≤ 25 files referencing `RawCullViewModel`, ≤ 150 graph edges, and `+BurstGrouping.swift` is gone.

Result: —

### Phase 5: Optional and open items

- Steps 17–18 only if you want them; they're tidiness, not risk.
- **The Deep AI Review / Combined Review decision** can be made at any time. If the answer is "fold it in", do that *after* step 15. The burst workflow is the code that calls Deep Review, so it's simpler to change once it's in its own owner.
- Re-run graphify at every release, and add a row to the table below.

## Graph history

Add a row after every merged step, using the numbers from `rebuild.py`.

| Date | After step | `RawCullViewModel` edges | Main VM cohesion | Stored props | Files referencing VM | Notes |
|---|---|---|---|---|---|---|
| 2026-11-20 | baseline | 399 | 0.02 | 103 | 73 | |
| 2026-11-20 | 6 | 385 | 0.03 | 63 (91 at baseline by the same count) | 73 | steps 1–6 |
