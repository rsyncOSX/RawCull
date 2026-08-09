# Phase 7 — bounded accessibility audit

## Outcome

Phase 7 adds native keyboard and assistive-technology semantics to the bounded
3.0.0 inventory without changing backend selection, model consent, destructive
actions, or genuine image click handling.

Saved catalog and file-record rows are now plain native buttons. Their action,
split-view selection reset, hover behavior, and row-wide layout are unchanged.
Selected rows expose the selected trait and announce their file count, rating,
date, and selection value.

## Click and action invariants

The image gestures remain in the same order and invoke the same closures:

| Surface | Existing pointer behavior retained | Added assistive action |
| --- | --- | --- |
| Normal thumbnail | Double click opens preview; single click selects | Default selects; named action opens preview |
| Rated thumbnail | Double click opens preview; single click selects | Default selects; named action opens preview |
| Comparison pane | Single click selects; double click selects and toggles zoom when allowed | Named select and zoom actions |
| Main/zoom thumbnail surfaces | Existing simultaneous gestures and keyboard handling untouched | Existing controls receive explicit names and values |

Only SavedFiles rows that had one action were converted to `Button`. No image
surface was converted to a button, so single- and double-click arbitration is
not changed.

## State announcement matrix

| Surface | Name/value/action coverage |
| --- | --- |
| Image tiles and comparison | Filename, rating, primary/multiple selection, semantic result rank, select/open/zoom actions |
| Rating controls | Current rating, target rating, selected trait, native enabled state |
| Image source | Thumbnail, extracted JPEG, embedded JPEG, or developed RAW; unavailable RAW stays disabled |
| Focus controls | Focus-map availability and shown/hidden value; camera focus-point shown/hidden value |
| AI settings | Model capability and location/error; active CLIP or Vision feature-print fallback; saved burst backend evidence |
| Model downloads | Checking/readiness, licence accepted/required, percentage, validation, installation, removal, and failure |
| Semantic search | CLIP descriptor, indexed/catalog count, indexing/search/result/empty/failure state, and cancellation |
| Deep Review | SAM 3 action purpose, prompt target, candidate progress, recommendation, confidence, failure, cancellation, apply, and close |

Decorative status icons and shortcut glyph duplicates are hidden. Content and
interactive descendants remain exposed.

## Automated verification

- `AccessibilityPresentationTests` locks the exact spoken values for SavedFiles,
  image selection/rating, model availability/licence/download failure and
  progress, CLIP semantic-search coverage/results, and SAM 3 Deep Review
  progress/confidence.
- Existing keyboard-action suites cover burst review, thumbnail navigation,
  loupe, zoom overlay, and image-source state.
- Focused AI suites cover download consent/actions, semantic-search UI state,
  and Deep Review cancellation/results.
- At the Phase 7 commit, the exact smoke manifest enumerated 169 unique tests
  and passed all 169. Later phase counts are recorded separately.
- SwiftFormat lint passes for every touched Swift source.

## Hands-on VoiceOver release checklist

The following checks require a signed interactive app session and remain part
of the Phase 9/10 release matrix rather than being represented as completed by
command-line tests:

1. Navigate and activate SavedFiles rows with VoiceOver and keyboard; confirm
   split-view selection and focus remain on the activated row.
2. Exercise single and double click on normal, rated, and comparison images;
   confirm selection and preview/zoom actions fire once each.
3. Traverse rating, source, focus, and burst-review controls in enabled and
   disabled states.
4. Exercise missing, corrupt, downloading, failed, installed, and licence-
   required model states; verify focus returns after every sheet, confirmation,
   and licence prompt.
5. Exercise semantic idle/indexing/searching/results/empty/failure/cancellation
   and Deep Review preparing/running/completed/failure/cancellation states.

Any click-count, selection, backend, licence-consent, model-removal, or cache-
clear regression rolls Phase 7 back at its commit boundary.
