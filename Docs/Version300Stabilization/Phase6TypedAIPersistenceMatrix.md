# Phase 6 — Typed AI persistence verification

This phase verifies RawCull 3.0.0's existing backend-aware persistence format.
It does not change record schemas, backend descriptors, pipeline signatures,
artifact codecs, model identifiers, licence keys, or resource layouts.

All new model descriptors and artifacts below are synthetic. They exercise the
same typed RawCull/PhotoAIKit boundaries without downloading or modifying a
production model bundle.

## Required matrix coverage

| Requirement | Deterministic coverage |
|---|---|
| Relaunch Vision, DataComp CLIP, OpenAI CLIP, and mixed backends | `PhotoAIKit Vision indexing produces complete reusable artifacts`; `Vision and CLIP artifacts coexist without cross-loading`; `dataComp and OpenAI artifacts relaunch without cross-loading` |
| Relaunch semantic, partial, and legacy artifacts | `superseded semantic hydration cannot publish an older backend`; `Partial indexing persists successes and isolates invalid payloads`; `Legacy burst artifacts migrate once into the per-file store`; `Legacy burst artifacts are rejected and the current schema rebuild loads` |
| Add, modify, remove, rename, and same-path byte replacement | `Durable indexing survives relaunch and reindexes only added or modified files`; `source add replace rename and removal preserve only compatible active records`; `replacing source bytes at the same path changes thumbnail identity` |
| Cancel before/during indexing, after partial persistence, semantic hydration/search, ranking, grouping, and Deep Review | `similarity indexing cancellation stops structured embedding workers`; `Cancellation during persistence retains only completed records`; `superseded semantic hydration cannot publish an older backend`; `Cancellation returns to idle and ignores a late provider response`; `cancelling similarity ranking stops its owned distance helper`; `cancelled burst analysis cannot apply a late cache result`; `Cancelling Deep Review cancels the owned in-process task` |
| Per-record persistence failure retains usable session results | `a per-record write failure retains usable session artifacts and returns idle` |
| Model switch, disable, missing/corrupt/restore, fallback, and licence gates | `CLIP enablement and exclusive model selection persist`; `Composition root reports the complete Phase 1 capability surface`; `Missing and corrupt model resources recover after restoration`; `Coordinator blocks download before invoking its service`; `Verified acceptance gates and unlocks a ready download`; `A changed licence checksum invalidates prior acceptance` |
| Thumbnail, similarity, subject-mask, and model-resource clears remain independent | `independent cache clears preserve ratings settings decisions models and licences`; `migration removes only legacy thumbnail JPEGs`; `thumbnail representation changes preserve Vision CLIP and SAM identities` |

## Acceptance evidence

- Backend and pipeline lookup precede artifact decoding. The two CLIP model
  fingerprints persist side by side, and a Vision lookup cannot load either.
- Indexing, semantic search, grouping, ranking, Deep Review, and persistence
  cancellation tests all end in idle/non-running state. Superseded generations
  cannot publish into the replacement backend or query.
- A failed record write is reported separately while every valid generated
  artifact remains usable in the current session. Relaunch restores only the
  record that actually reached durable storage.
- Independent clearing preserves ratings/saved-record storage, settings, burst
  decisions, model resources, and licence acceptance whenever those namespaces
  are unrelated to the requested clear.

No persistence migration is required by the verified matrix.
