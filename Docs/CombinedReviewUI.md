# Combined Review presentation

Combined Review opens as its own main view from the AI icon with a plus sign
beside AI Analysis in the toolbar. Its source picker supports selected and tagged
images; AI Analysis retains SAM 3 + CLIP, Qwen Vision and Objects.

The Combined Review screen has two connected modes. Photo-first is the default:
it shows the selected image's retained overview, concise findings, important
evidence limits, coverage and the existing rating controls. Reviewed-region
overlays are optional. The filmstrip is capped at 140 points in this
workspace to leave room for the image and findings.

Inspect evidence opens the Evidence workspace, selects the finding and resolves
its supporting crop from the finding's region or cited observation. Findings,
Coverage & limits and Technical record are separate sections. Returning to
Photo-first keeps the selected image, region and rating. Both modes have draggable column dividers; resizing the photo or evidence pane
resizes the adjacent column. Overview images preserve their aspect ratio and grow
with the pane width. Layouts stack in narrower windows based on container width,
so loading a retained crop does not switch layouts or interrupt Region selection. The image picker also exposes saved reviews outside the current input
selection; ratings are available only for files in the current input selection.

Review settings, retention cleanup, selection comparison and run diagnostics
remain available through disclosure controls. Full measurements are shown as
name/value rows. The complete structured record can be inspected and copied as
JSON, preserving the original values, IDs, conflicts, limitations and provenance.
Repeated limitation reasons are shown once in the compact coverage presentation;
the structured record retains every original entry.

No quality score, calibrated sharpness verdict, independent confirmation or new
photographic conclusion is inferred by the presentation layer. Failed synthesis
can expose available observations, explicitly labeled as observations only.
Selecting an image without a review shows an empty state rather than another
image's findings. Missing retained images never erase the report or measurements.

Validation includes presentation tests for image ownership, crop-reference
resolution, unsynthesized observations, conflicts, omitted coverage and full-
precision JSON round trips, plus layout rendering at 520 and 1024 points.
