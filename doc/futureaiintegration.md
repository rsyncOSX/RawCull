# Future AI Integration for RawCull

## Recommendation

Use a modified version of the clean-port approach:

**Keep RawCull as the canonical application and create a macOS 27 AI integration branch inside the RawCull repository. Do not create another permanent RawCullAI repository.**

Optionally, that branch can contain a `RawCullAI` target so RawCull and RawCullAI can be installed side by side during beta testing. Both targets should reference the same physical source files.

Use RawCullSAM3 as a reference implementation and source of selected AI components—not as the future application base and not as a tree that must be made identical to RawCull.

## Why this is the safest approach

The reusable AI architecture is now in good condition. PhotoAIKit has clean products for contracts, backends, storage, and workflows, with model fingerprints and actor-owned services. Its macOS 27 and Swift tools 6.4 requirements are explicit in its `Package.swift`.

The RawCullSAM3 application integration is promising, particularly its `RawCullAIContainer` composition root, but its application layer is not yet a cleaner replacement for RawCull.

The source comparison found:

| Measure | RawCull | RawCullSAM3 |
| --- | ---: | ---: |
| Application Swift files | 148 | 195 |
| Application Swift lines | 23,923 | 28,007 |
| Common Swift paths | 139 | 139 |
| Identical common paths | 77 | 77 |
| Different common paths | 62 | 62 |
| Swift Testing tests | 222 | 269 |

The 62 changed shared files look worse than they really are: 40 differ by no more than 25 lines. Many of the 56 RawCullSAM3-only paths are small type extractions or file moves rather than AI implementations.

The important differences are concentrated in risky places:

- Deep-review orchestration remains inside the roughly 1,300-line `RawCullViewModel+BurstGrouping.swift`.
- Subject-aware scoring has expanded `FocusMaskEngine+Scoring.swift` to roughly 1,370 lines.
- Some views access `aiContainer` directly, coupling UI code to the application's composition root.
- Helper state is inferred from exact status strings instead of a typed state model.
- The referenced `RawCullSAM3MaskBuilder` executable has no source-controlled target or implementation.
- Several `try?` paths hide whether degradation came from a missing model, invalid resources, decoding, inference, or cache failure.

These issues are fixable, but they make a whole-tree consolidation into RawCullSAM3 unnecessarily risky.

The two repositories also have no common Git commit ancestry. Synchronizing them is therefore manual reconciliation rather than an ordinary Git merge. Creating a third permanent repository would reproduce this problem.

## Code-quality assessment

### PhotoAIKit

PhotoAIKit is the correct reusable boundary. It now owns:

- SAM 3 and CLIP providers.
- Vision feature-print fallback.
- Model capabilities, resource resolution, and fingerprints.
- Similarity artifacts, persistence codecs, and fallback indexing.
- Subject-mask storage, catalogs, quality analysis, and selection.
- Segmentation batching and transport events.

Its use of separate contracts, backends, workflows, and storage products is a strong architectural choice. Generic AI behavior should continue to move there when it is genuinely reusable.

RawCull-specific focus algorithms, culling policy, file models, security-scoped access, application paths, and UI behavior should remain outside PhotoAIKit.

### RawCullSAM3

RawCullSAM3 is a credible reference integration. Its strongest application-level decisions are:

- A central AI composition root.
- Narrow protocols between RawCull file models and PhotoAIKit services.
- Package-owned inference and cache implementations.
- Explicit CLIP-to-Vision fallback.
- Model-aware artifact invalidation.
- Additional AI-specific Swift Testing coverage.

Its weakest area is feature isolation above the composition root. AI state and orchestration still leak into the central view model and several large UI and focus-scoring files.

### RawCull

RawCull should remain the canonical base because it contains the current non-AI product development, has the smaller application tree, and is verifiable with the current stable toolchain. Its smoke test suite succeeds under Xcode 26.6.

One improvement worth carrying over from RawCullSAM3 is its Swift 6 test-target configuration. RawCull's application target uses Swift 6, but its test target currently declares Swift 5 mode. That should be upgraded separately and verified before or during the macOS 27 migration.

## Work before Xcode 27 integration

Until the macOS 27 toolchain is ready:

- Continue normal product development only in RawCull.
- Limit RawCullSAM3 changes to AI experiments and improvements that make the integration boundary easier to port.
- Continue reusable inference, storage, cache, identity, and workflow work in PhotoAIKit.
- Do not spend time making every non-AI RawCullSAM3 file match RawCull.
- Do not add additional AI orchestration directly to `RawCullViewModel`.
- Decide whether SAM mask generation will use a source-controlled helper executable or an in-process pipeline.
- Measure memory use before choosing in-process SAM execution for production.

The missing helper decision is a hard prerequisite. If retaining the external worker design, it needs:

- A source-controlled executable target and entry point.
- Request decoding and security-scoped resource lifetime management.
- Raw decoding and segmentation-pipeline execution.
- Progress, failure, cancellation, partial-result, and exit-code handling.
- Build and packaging verification.

## Suggested repository and branch arrangement

During the beta period, use one Git history:

```text
RawCull repository
├── main                         macOS 26 production
└── macos27-ai branch
    ├── shared RawCull sources
    ├── RawCullAIIntegration
    ├── optional RawCullAI target
    └── PhotoAIKit dependency
```

Regular RawCull development can be merged into the AI branch using normal Git history. The branch diff should then contain only intentional AI integration and macOS 27 changes.

If side-by-side beta testing is useful, add a second application target on the AI branch with a separate bundle identifier. Do not duplicate the shared Swift source tree for that target.

After macOS 27 becomes the RawCull minimum deployment target, merge the integration branch into the canonical application and retire the temporary target. If RawCull must continue supporting macOS 26, retain a separate target or investigate availability-gated backends once Xcode 27 behavior can be tested properly.

## Integration order

### Phase 1: Platform and composition boundary

- Raise the integration branch to the required macOS and Swift toolchain baseline.
- Add the PhotoAIKit products.
- Preserve RawCull's bundle identifier, settings keys, cache directories, and Application Support paths.
- Port model-location adapters and a RawCull-owned AI composition root.
- Introduce structured capability state for CLIP, SAM 3, Vision, mask storage, and worker availability.

### Phase 2: Similarity

Port CLIP similarity first because it has the narrowest visible feature boundary and RawCull already has Vision-based similarity behavior.

- Port RawCull-aware image decoding.
- Store descriptor-complete PhotoAIKit similarity artifacts.
- Use whole-batch CLIP-to-Vision fallback.
- Include model fingerprints and artifact versions in cache signatures.
- Validate complete descriptors for both disk and in-memory reuse.

### Phase 3: SAM storage and overlays

- Configure package memory and disk stores using RawCull-owned locations.
- Port `FileItem` and `AIImageSource` adapters.
- Port mask inventory and quality metadata.
- Implement the selected helper or in-process generation path.
- Expose cached overlays through a narrow provider rather than `aiContainer` traversal from views.

### Phase 4: Subject-aware focus evidence

Keep focus policy in RawCull, but extract SAM-specific subject scoring from the large focus engine into a component such as `SubjectMaskFocusScorer`.

The component should accept decoded focus evidence and a subject mask, then return explainable subject-detail evidence. It should not mutate ratings or choose winners.

### Phase 5: Deep AI review

Port deep review last and place its workflow in a RawCull-owned `DeepAIReviewFeature` or service.

The service should:

- Select candidate files and prompt policy.
- Ask PhotoAIKit to acquire and evaluate masks.
- Ask RawCull focus scoring for subject-detail evidence.
- Return a proposed winner, confidence, reasons, and cautions.

`RawCullViewModel` should only start or cancel the operation and apply user-confirmed actions.

## Required application-boundary improvements

During the port:

- Replace Boolean and string-based helper state with a typed enum such as `idle`, `preparing`, `running(progress)`, `completing`, `failed(error)`, and `completed`.
- Stop views from accessing the AI composition root directly.
- Keep the composition root hidden behind feature models and narrow protocols.
- Preserve structured operational errors instead of collapsing failures with `try?`.
- Separate deep-review orchestration from burst-management state.
- Separate SAM subject scoring from the general focus-scoring implementation.
- Keep AI-produced decisions explainable and reversible.

## Testing strategy

- Preserve all current RawCull tests during the port.
- Port AI-specific RawCullSAM3 tests individually rather than replacing complete test files.
- Keep generic provider, serialization, storage, fallback, identity, and concurrency tests in PhotoAIKit.
- Keep RawCull adapter, worker-lifecycle, focus-evidence, ranking, and UI-state tests in RawCull.
- Upgrade the RawCull test target to Swift 6 and retain strict concurrency checking.
- Keep tests parallel-safe and isolate file-system/cache state per test.
- Run a CI matrix for stable RawCull and the macOS 27 AI branch while both exist.
- Add representative real-photo validation for correctness, memory pressure, fallback rates, cancellation, and cache invalidation.

## Final decision

The best long-term result is **one RawCull codebase with optional AI capabilities**, not two synchronized application repositories.

Therefore:

- Do not use RawCullSAM3 as a whole-tree replacement for RawCull.
- Do not create a third permanent application repository.
- Keep RawCull as the canonical integration destination.
- Use RawCullSAM3 as a reference and donor for deliberate AI changes.
- Perform the clean AI port on a macOS 27 branch or target within the RawCull repository.
- Retire RawCullSAM3 after feature parity and deliberate data migration are complete.

This preserves the strong PhotoAIKit boundary, avoids importing unrelated fork drift, and gives RawCull a maintainable foundation for future local AI models.
