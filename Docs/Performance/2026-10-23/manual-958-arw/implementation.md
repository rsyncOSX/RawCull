# Performance implementation — 2026-10-23

The user authorized all three planned changes after the baseline was saved. Baseline reports and measurements remain unchanged. This implementation has not yet been reprofiled against the real 958-ARW catalog.

## Applied changes

1. **Sharpness presentation:** `sharpnessScoringTargetCount` determines count without filename sorting or constructing the ordered scoring array. Button availability and tooltip use this count. Actual scoring still obtains ordered target files; only branches needing filename order sort them. Visible selected/rated order and semantic scope retain their previous behavior.
2. **Zoom navigation:** a view-model-owned memoized projection supplies ordered files, catalog membership and an ID-to-index lookup. Selection-only changes reuse it. Observable catalog, filtered/rating and context revisions plus source, filter and analysis-mode values form the key. Every lookup reads that key before checking the ignored cache, preserving observation dependencies on cache hits. Catalog replacement releases the old projection. Contextual order, stale-ID filtering, empty-context fallback and analysis order remain supported.
3. **Grid resizing:** `GridThumbnailResizer` uses a Core Graphics bitmap with high-quality interpolation instead of `NSImage.lockFocus`/AppKit drawing. It produces a maximum 200-pixel dimension independent of display scaling, clamps thin dimensions to at least one pixel, and does not upscale smaller images. RGB source color spaces are retained, with an sRGB destination fallback for other source spaces. Fully normalized source orientation is retained. Cold extraction passes its already resolved CGImage to avoid resolving it again. Changes affect the grid copy only; preview decoding, JPEG encoding quality, cache keys, bounded disk-save ownership and preview RAM admission are unchanged.

The former drawing path used logical NSImage dimensions and could produce display-dependent backing pixel sizes. The new pixel contract is explicit and tested. Include a visual check of grid sharpness/color in the next real-catalog run, especially with large grid cells on Retina.

## Validation

- Focused Debug tests: **114 tests passed, 133 executions including parameterized cases**, zero failed or skipped. The final rerun after the target-count state-read refinement also passed. Xcode result summary is saved in `implementation-test-summary.json`; source fingerprints and Release build identity are saved in `implementation-validation.json`.
- Covered new count/description behavior, semantic target scope, navigation ordering and invalidation, selection-only reuse, observation on cache hits, pixel dimensions/no-upscale behavior, orientation/transparency/wide-gamut color, and existing culling, keyboard, cache identity/admission, orientation-normalization, thumbnail gate and bounded-save regressions.
- SwiftLint: no errors. Warnings remain for existing long lines, analyzer-rule configuration, and the view model now reaching 405 lines against the 400-line style threshold.
- `git diff --check`: passed.
- Release build: **passed**, optimized arm64 RawCull scheme, coverage disabled. Binary UUID: `19A8A349-82AF-312A-87B8-BCB7F67E8FDA`. App: `/Users/thomas/Library/Developer/Xcode/DerivedData/RawCull-gcnyfiqsskrykfdbxvxmozmmdpac/Build/Products/Release/RawCull.app`.

Xcode tests used the existing default derived-data/package cache because the old `/tmp/RawCull-333-readiness` checkouts were incomplete. Package versions remained pinned, automatic resolution/update disabled, and code coverage disabled. A target-only Release attempt failed with unresolved `Crypto`/`EventSource` package modules; verification was retried using the complete arm64 RawCull scheme dependency graph.

Temporary validation logs: `/tmp/rawcull-performance-update-tests.log`, `/tmp/rawcull-performance-update-tests-final.log`, `/tmp/rawcull-performance-update-release.log`, `/tmp/rawcull-performance-update-lint.log`. Tests ran on macOS 27.0.1, arm64. No source-performance percentages are claimed from unit tests or a successful build.

## Next user recording

1. Use Product → Profile, confirm Release, and keep the same 958 ARWs and existing cache configuration. Rebuild so the recording uses this working tree.
2. Save a separate catalog-open/scan capture and a browsing/zoom capture. For the latter, wait until background preparation finishes; record 60–90 seconds of the same navigation/zoom actions. Optionally capture a third browsing-during-preload run.
3. Stop recording **before** closing RawCull to exclude tracing cleanup at termination.
4. Save under new names, for example `opencatalog-after.trace` and `browsing-after.trace`, preserving the original recordings.
5. SwiftUI captures can check the previous hitch pattern, with the existing overhead/empty-table limitations. A separate Time Profiler run is useful for cleaner CPU attribution, but a direct speedup claim requires a matched pre-change Time Profiler baseline too.
6. Record storage, camera/file sizes, source mode, grid-cell setting, preview limits and window/display configuration. Note whether scanning/preload completed and whether images were previously visited.

Compare the sharpness target getter, navigation projection, grid resize/preload stacks, interactive hang windows and repeated-action responsiveness. Keep tracing cleanup, background-preparation state and cache conditions separate. The current baseline has no allocation/footprint measurements for a memory comparison.
