# View composition

Each screen composes focused presentation views. Session models own review state;
presentation models own transient asynchronous results. Rendering components do not
load images or make culling decisions.

| Screen | Presentation | Coordination |
| --- | --- | --- |
| Zoom | ZoomImageCanvas, ZoomOverlayChrome, ZoomOverlayControls, RAWExposureInspectionControls | ZoomSessionModel, ZoomNavigationPresentation, ZoomOverlayAnalysisCoordinator, ZoomKeyboardController |
| Loupe | LoupeImageStage, LoupeImageContent, LoupeImageControls, LoupeMetadataOverlay | LoupeSessionModel, LoupeFocusPresentationModel, SubjectOutlinePresentationModel, LoupeKeyboardController |
| Burst | BurstImageStage, BurstWorkspaceHeader, BurstWorkspaceFilmstrip, BurstEvidenceShelf | BurstWorkspaceSessionModel, BurstWorkspaceImageCoordinator, BurstKeyboardController |
| Culling | CullingQueueHeader, CullingBurstGroupCard, CullingGridThumbnail | Existing grid projection and selection coordinator; the parent owns scrolling and selection orchestration |
| Comparison | ComparisonPager, ComparisonPane, ComparisonImagePaneView | ComparisonSessionModel, ComparisonGridImageCoordinator, ComparisonKeyboardController |
| Object Analysis | ObjectPhotoDetailView, ObjectInstanceList, ObjectPhotoAssessmentSection, ObjectOverviewImage | ObjectPhotoPreviewModel and the existing feature |

Shared rendering uses ImageReviewRasterOverlay and AnalysisImageCanvas. The latter
provides one aspect-fit rectangle for image overlays; preserve the distinction between
camera autofocus coordinates and bottom-origin object boxes. OverlayControlCapsule
owns common control chrome while individual controls retain their behavior and
accessibility descriptions.

AnalysisPreviewPreparation shares image/focus preparation without changing each
feature's requested preview resolution. ImageReviewSubjectOutlineLoader preserves
the original mask when contour rendering is unavailable. ReviewKeyMonitor owns only
registration and removal: screens retain their event scope and accepted-key policies.

Keep task identities and cancellation at an explicit owner. Loupe focus requests
reject obsolete completions and preserve the displayed mask during source changes.
Object detail selection stays local to its view. Exposure slider drafts remain local
to RAWExposureInspectionControls and commit only when dragging finishes.

Prefer a separate View type for an independent section. Pass its required values,
bindings and actions; avoid adding unrelated flags to a universal viewer. Reuse existing
rating badges, SettingsCard, image-source controls and review policies.
