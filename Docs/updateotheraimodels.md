# Evidence rules in the other AI analysis modes

Updated 13 October 2026 after the combined-v21 review. These changes transfer the applicable evidence rules while retaining each mode’s purpose. Combined Review orchestration and deterministic sentence selection are not copied into the other workflows.

## Qwen photo analysis

Photo assessment uses response schema version 2. Composition, exposure and subject visibility each have a nullable score and a separate nullable evidence sentence. A score requires its own nonempty, bounded evidence; unsupported criteria return null for both fields. The overall score is unavailable when any component abstains rather than treating missing evidence as a zero or silently reweighting it.

The whole-image path has no independently qualified anatomical evidence. The prompt requires eyesOpen=null, and non-null eye claims are rejected. Scores and confidence are presented as model judgments, with criterion evidence and preview/input-resolution limits visible in the inspector.

Intentional plain-text answers remain available for requests outside the assessment schema. JSON-like output that fails structured validation is retained as a rejected response (up to 8192 characters) and counts as failure, not a successful freeform assessment. Required keys, version, ranges, finite confidence, bounded lists and evidence/score pairing are validated.

## Object Analysis

Object assessment uses response schema version 2. Every non-uncertain focus judgment requires a focusEvidence object containing the matching cropID and a visible observation. Each strength and problem requires its own evidence object in matching array order. Cross-crop references and mismatched registered concepts are rejected. Global strengths/problems remain empty; supported judgments belong to their numbered object with crop evidence.

Focus evidence must describe the requested crisp/soft/smeared distinction. Conservative wording checks reject explicit contradictions between focusQuality and descriptive prose; common background-blur and negated-sharpness wording does not count as a contradictory sharp subject claim. These checks do not prove semantic consistency for arbitrary language or establish photographic accuracy.

SAM regions do not independently verify facial anatomy. Expression stays null; unverified non-null expressions fail admission. The inspector distinguishes model focus/visibility judgments from measured AF and focus-map locations and shows crop evidence, source thumbnail/board limits and rejected assessments. Failed assessment text is retained up to 8192 characters. Existing explicit retry behavior is preserved; no automatic inference repair calls are added.

## SAM 3 / Deep Review

The legacy promptVerified field is retained for compatibility and documented as requested-prompt mask availability. The new requestedPromptObtained accessor and inspector wording say that a usable mask was obtained, without claiming independently verified head/face anatomy. Ranking confidence is described as relative score separation under the available measurement conditions. Local detail scores are distinguished from overall photographic quality. Scoring behavior is unchanged, so existing measurement caches do not require invalidation for this terminology change.

## Shared diagnostics and compatibility

Both changed live response contracts require schemaVersion=2; old responses cannot silently enter the new assessment boundary. Qwen and Object results are session results rather than persisted assessment caches. Segmentation and search caches are not changed by the response-schema updates.

For optional model testing, set RAWCULL_AI_CAPTURE_DIR to a private output directory. The Qwen runtime used by both modes retains paired JSON and PNG files containing the request instruction, bounded response, token cap, request raster dimensions and declared model input capabilities. PNGs preserve the supplied request raster before backend preprocessing, not the encoder tensor. Text truncation is recorded. Directories must have private permissions; optional capture failures do not alter inference results. Existing Object Analysis diagnostic capture remains available.

Automatic repair budget is zero for these modes; this update adds no model calls. Similarity and semantic search retain their matching purpose. No evidence from this task establishes a defect in their preprocessing, geometry or cache compatibility, so no speculative changes are applied there.

## Verification and app testing

All 48 focused tests across five suites pass. Focused regression coverage checks Qwen abstention, malformed output and failed-result retention; Object crop ownership, evidence alignment, schema compatibility, expression abstention and focus contradictions; existing Object workflow retries; Deep Review behavior; and accessibility presentation. Logs: /private/tmp/rawcull-other-ai-validation.log. Smoke enumeration confirms 355 unique enabled identifiers; the expected count is updated to match the actual manifest. The final app build and an additional 17-case Object Analysis check pass. git diff --check passes.

No new installed-model inference was performed. Start real app testing with Qwen and Object Analysis on the same six photographs, retaining diagnostics where useful. Validate usefulness and subject relevance rather than accepting higher coverage as proof of quality. The stricter contracts may expose further model compliance failures. The recurring MDB_MAP_FULL errors remain a separate unresolved storage issue.
