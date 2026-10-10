# Combined Review phase 2 source contract

Date: 9 October 2026

Status: source and coordinate foundation implemented and deterministic gate passed.

## Decision and scope

The phase 1 geometry decision in [the input contract](combined-review-input-contract.md)
remains the prerequisite for encoder geometry. The new service describes geometry;
it does not qualify another model or implement a replacement inference preprocessor.
Future run admission must match the model/runtime fingerprints before supplying a
`ReviewEncoderGeometry` to crop planning.

Engineering implementation and source-contract review: Codex. This records an
engineering self-review, not external photographic qualification. Phase 2 adds no
synthesis, quality scoring, ranking, or UI. Phase 3 may build the run/evidence contract
on this foundation.

## Declared sources and renders

`ReviewImageSourceService` is independent of grid thumbnails and preview caches.
It retains the catalog grant throughout decoding, runs off the caller's actor,
checks cancellation, and checks the file snapshot before and after the operation.
The source identity includes the file snapshot, fidelity, dimensions, render policy,
recipe version, decoder OS, and recorded parameters. The file snapshot hashes path,
resource identifier, size, and modification date; it is not a whole-file content hash.
Persisted stage compatibility/content validation remains phase 3 work.

- JPEG/PNG/TIFF/HEIF: orientation-normalized full raster; overview generated afterwards.
- Camera preview: largest decodable camera-authored JPEG from Sony/Nikon parser
  locations, with ImageIO embedded-only fallback. No sidecar substitution, generated
  RAW thumbnail, or grid-cache reuse. An allocation refusal does not choose a smaller
  preview. Preview processing is explicitly unknown.
- RAW detail: fresh `CIRAWFilter` per request, full scale, draft mode disabled, SDR
  output. An unsupported/lazy decoder with no usable native dimensions/output falls
  back to the embedded preview with `rawDemosaicUnavailable` recorded. A missing
  preview is an image decode failure. Allocation refusal is a failure, not a downgrade.

Appearance and technical policies have separate immutable outputs and identities.
Technical RAW parameters match the existing Deep Review recipe: sharpness 0,
detail 0.6, contrast 1, exposure 0. Decoder noise reduction defaults are retained and
recorded. The full recorded recipe additionally includes decoder version, scale,
draft mode, extended range, baseline exposure, shadow bias, global/local tone controls,
white balance, lens/gamut correction, moire/despeckle, and noise parameters. Appearance
uses recorded decoder defaults. No scoring algorithm or existing decoder was changed.

Inputs are color managed through Core Image's extended-linear sRGB working space to
sRGB RGBA8. HDR raster inputs use `toneMapHDRtoSDR`; gain-map expansion is disabled.
RAW uses the decoder's recorded tone/exposure settings and SDR output. Higher precision
source values are not retained, and these SDR renders cannot establish RAW recovery
latitude. This render version must not be treated as interchangeable with old scoring
renders merely because their sharpening parameters match.

## Coordinates, crops, and retention

All public rectangles use orientation-normalized pixels with a top-left origin.
Mask/region proposals use normalized top-left coordinates; callers must convert
Vision's bottom-left coordinates explicitly. `ReviewOrientationTransform` maps all
8 EXIF orientations, including mirrors and transposes. Decoded dimensions must match
the recorded orientation transform or the source fails with `unsupportedAlignment`.

Source/overview and normalized-mask mappings are deterministic. Cross-render mapping
requires the same file snapshot, fidelity, orientation transform, and dimensions.
Camera-preview-to-RAW registration is deliberately unavailable: equal aspect ratios
alone do not establish matching active areas or lens corrections. For RAW technical
measurement with appearance masks, use matching full RAW appearance/technical renders;
otherwise acquire registration evidence or report the unavailable mapping.

Regions have stable source/purpose/rectangle/padding IDs, requested and unclipped padded
rectangles, integer enclosing source crops, edge-clipping flags, and encoder traces.
Crops come from the full declared source before any overview/model resize. Stale regions
from another source/render are rejected. No annotation or lossy JPEG encoding is added.
`pngData(for:)` is a lossless exact-CGImage retention hook; storage/retention policy and
floating-point tensor retention remain later work.

The trace describes stretch or the pinned CLIP integer shortest-side resize and center
crop, encoder dimensions, retained source rectangle, horizontal/vertical effective
scale, upscaling, and whether the intended region survives. A rectangular CLIP overview
can lose its edges; planning must use that flag rather than claim full coverage.
The rectangle describes geometric coverage, not the bicubic filter's entire support.

## Validation

`ReviewImageSourceTests` has 12 enumerated contracts / 22 concrete invocations, all
passing without loading or downloading models:

- All eight EXIF orientations, actual corner identity in source crops, encoded/source
  and source/overview round trips.
- Landscape, portrait, square, extreme-ratio geometry, normalized-mask mapping, and
  encoder/source round trips.
- Padding, integer bounds, clipping, stable IDs, invalid rectangles, upscaling, and
  explicit center-crop coverage loss.
- Separate render identities, compatible raster mapping, stale-render crop rejection,
  and lossless PNG reload.
- Display P3 ICC conversion checked against converted color values, rather than just
  the output profile tag.
- PQ HDR TIFF loaded through the source service and compared with explicit Core Image
  HDR-to-SDR rendering.
- Unsupported RAW fallback with a fake embedded source, no sidecar substitution,
  cancellation, pixel/byte admission limits, and integer overflow rejection.
- Actual pinned Qwen and CLIP preprocessors applied to the phase 1 source fixture and
  a separate source crop. Qwen retains the red overview corner; CLIP removes it from
  the overview, then retains it in the square detail crop. Inputs are finite.

`make test-smoke`: 270 unique identifiers verified; 269 passed, zero failures, one
expected opt-in real-photo Qwen skip. Including parameterized cases: 304 passed and
one skipped. The AI import-boundary and whitespace checks also pass. SwiftLint reports
no errors on the new files; repository formatting has been applied.

Reproduce the deterministic suite with:

```sh
xcodebuild test -project RawCull.xcodeproj -scheme RawCull \
  -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  -only-testing:RawCullTests/ReviewImageSourceTests -enableCodeCoverage NO
```

The memory test records `full-source-memory.json` as a Swift Testing attachment.
Export it with `xcrun xcresulttool export attachments --path <result.xcresult>
--output-path <directory>`.

## Working set and limits

The default admission limits are 24 million source pixels and 2,000,000,000 estimated
working bytes. The conservative estimate is 80 bytes per source pixel, with overflow
checks before allocation. Full raster and RAW demosaic sources exceeding a limit fail before full decode.
Embedded camera previews use an ImageIO thumbnail fallback bounded by the admission
budget and a 4096-pixel longest edge. Reduced previews retain orientation-normalized
coordinates and record original/decoded dimensions and reduced fine-detail evidence
in the report limitations. Full-size limits remain unchanged. Callers may only raise
limits after measuring their workload and reserving headroom for retained renders and models.

The [smoke-run measurement](CombinedReviewSourceFixtures/full-source-memory-smoke.json)
records a 6000 × 4000 full raster, a 2048-pixel overview, a source crop, and lossless
retention. Retained source/overview images account for 107,182,080 bytes. The process
high-water mark was 1,001,422,848 bytes, from an initial 326,516,736 bytes. This includes
fixture creation, the application test host, Core Image, and concurrent smoke tests;
it is not an isolated decoder allocation measurement. The admission estimate was
1,920,000,000 bytes on an 18 GiB machine.

The [isolated follow-up](CombinedReviewSourceFixtures/full-source-memory-isolated.json)
ran only the same working-set fixture with `test-without-building`: initial process
high-water 286,982,144 bytes, final 863,830,016 bytes, the same 107,182,080 retained
image bytes, and no concurrent test cases. Its high-water increase is 576,847,872
bytes; it still includes TIFF fixture creation and the application host, so it must
not be presented as a CIRAWFilter allocation guarantee. The test passed.

A [six-file Sony ARW probe](CombinedReviewSourceFixtures/phase5-arw-smoke.json) now
records two eligible 6000 × 4000 RAW decodes, source crops and technical alignment,
four 8640 × 5760 full-RAW admission refusals, and bounded preview review for all six.
This is a narrow local source check, not camera-format-wide qualification.
Wider RAW-format qualification, HEIF gain-map-specific behavior, decoder GPU/unified-memory
peaks, and operation with resident Qwen/SAM models remain unmeasured.
The deterministic RAW fallback fixture is not a real RAW demosaic validation. Larger
RAWs remain rejected by default; raising the cap or advertising camera-format support
requires real-file probes. Phase 6 still owns measured system-wide resource policy.
