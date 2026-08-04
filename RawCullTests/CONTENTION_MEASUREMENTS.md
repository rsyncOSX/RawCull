# RawCull 3.0.0 contention measurement matrix

Phase 5 adds passive counters to the Memory Console for cold thumbnail
decodes, exact-key duplicates, coalesced waiters, cancellations, active/peak
thumbnail work, AI inference starts, semantic hydration, model downloads, and
time to first usable grid. The console remains observational and does not own
or cancel any work.

## Deterministic automated profiles

`ThumbnailContentionTests.fixedCatalogDuplicateProfiles` runs fixed synthetic
small, medium, and large demand bursts of 12, 120, and 1,200 requests. For each
profile, every request has the same complete thumbnail identity. The required
result is one cold producer, `N - 1` coalesced waiters, peak cold work of one,
all waiters resumed, and no retained continuation.

The suite also verifies the existing six-slot interactive loader bound, the
four-or-fewer scan preload bound, cancellation of one versus the final shared
waiter, catalog-scoped grid gating, and gate draining.

## Real-catalog capture protocol

Use fixed 12-, 120-, and 1,200-image RAW catalogs. Start a fresh Memory Console
capture for each of these presentation states:

| State | Grid path | Independent work that must remain live |
|---|---|---|
| Normal grid | `ThumbnailLoader` | catalog preload |
| Rated grid | `ThumbnailLoader` | catalog preload |
| Similarity indexing | `ThumbnailLoader` presentation | selected Vision/CLIP indexing |
| Semantic search | `ThumbnailLoader` presentation | hydration and text inference |
| Deep Review | `ThumbnailLoader` presentation | SAM 3 review |

For every capture, record first usable grid time, cold decodes, duplicates,
coalesced waiters, cancellations, peak thumbnail work, and the applicable AI
start counters. Run a user-requested model download concurrently in the large
profile and confirm that its progress is not paused or cancelled. A backend
descriptor, AI result, or progress-state change invalidates the run.
