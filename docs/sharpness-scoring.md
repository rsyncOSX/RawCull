# Sharpness Scoring

RawCull can automatically rank every image in a catalog by sharpness, so the sharpest frames rise to the top and out-of-focus or motion-blurred shots sink to the bottom. This page explains what the score means, how to run it, and how to interpret the results.

---

## Overview

When you click **Score Sharpness**, RawCull analyses each RAW file using a multi-step pipeline:

1. A small thumbnail is extracted directly from the ARW file — fast, no full RAW decode needed.
2. Apple Vision locates the main subject in the frame (a bird in flight, an owl against a blurred background, etc.).
3. A Laplacian-of-Gaussian edge-detection filter measures how much fine detail exists **inside the subject area only** — the background is ignored.
4. The 95th-percentile edge value is used as the raw score, so a single sharp feather edge cannot carry a blurry frame.
5. All scores are normalised against the sharpest frame in the catalog: that frame becomes **100**, and every other frame is expressed as a percentage of it.

Because scores are **relative to your catalog**, a score of 60 does not mean the image is soft — it means it is 60 % as sharp as the best frame in that session. Opening a catalog of sharper images will recalibrate the scale.

---

## Running a Sharpness Score

![Score Sharpness button in the grid toolbar](../figures/score-sharpness-button.png)
*Figure 1 — The Score Sharpness button appears in the grid toolbar.*

1. Open a catalog and wait for thumbnails to finish generating.
2. Click **Score Sharpness** (scope icon) in the toolbar above the grid.
3. A *Scoring…* label replaces the button while analysis runs. Progress is bounded — at most six images are analysed concurrently to avoid saturating disk I/O.
4. When complete, a coloured score badge appears on every thumbnail and the grid re-sorts automatically with the sharpest frames first.

You can re-score at any time — for example, after adjusting the Focus Mask Controls or switching the aperture filter. Click **Re-score** (the button label changes once scores exist).

---

## Reading the Score Badge

![Thumbnail grid with score badges](../figures/score-badges-grid.png)
*Figure 2 — Score badges appear in the bottom-left corner of each thumbnail.*

Each thumbnail shows a small badge in the bottom-left corner:

| Colour | Normalised score | Meaning |
|--------|-----------------|---------|
| Green  | 65 – 100        | Sharp — well-focused, fine detail visible |
| Yellow | 35 – 64         | Acceptable — slightly soft or minor motion blur |
| Red    | 0 – 34          | Soft — missed focus, camera shake, or significant motion blur |

The number in the badge is the normalised score (0–100). The sharpest frame in the catalog always shows **100**.

---

## Sorting by Sharpness

![Sort by Sharpness toggle](../figures/sort-sharpness-toggle.png)
*Figure 3 — The Sharpness sort toggle in the grid toolbar.*

After scoring, the grid sorts sharpest-first automatically. You can toggle this off and back on with the **Sharpness** toggle button in the toolbar. Turning the toggle off returns the grid to its previous sort order (typically by filename).

The same toggle is also available in the sidebar toolbar for the vertical and horizontal list views.

---

## Filtering by Aperture

![Aperture filter picker](../figures/aperture-filter.png)
*Figure 4 — The Aperture filter picker lets you focus on one shooting style at a time.*

Wildlife and landscape sessions are often mixed in the same catalog but have very different sharpness expectations. The **Aperture** picker lets you restrict scoring and sorting to one shooting style:

| Filter | Aperture range | Typical use |
|--------|---------------|-------------|
| All | All images | Default — no filtering |
| Wide (≤ f/5.6) | f/1.4 – f/5.6 | Birds, wildlife, portraits — subject isolation |
| Landscape (≥ f/8) | f/8 and above | Tripod landscape, architecture, macro — front-to-back sharpness |

Changing the aperture filter immediately re-filters the grid. If scores exist, the sharpness sort is re-applied within the filtered set.

---

## The Focus Mask Overlay

![Focus Mask overlay on a sharp owl](../figures/focus-mask-owl-sharp.png)
*Figure 5 — Focus Mask on a sharp frame: a tight red glow concentrated on feather edges.*

![Focus Mask overlay on a soft frame](../figures/focus-mask-owl-soft.png)
*Figure 6 — Focus Mask on a soft frame: faint, diffuse glow with no sharp edge lines.*

The **Focus Mask** overlay (toggle in the zoom window controls) renders the same Laplacian edge-detection output that the scorer uses, painted in red over the image. It is a direct visual representation of the score:

- **Tight, bright red lines** on subject edges → high edge energy → high score.
- **Faint, blurred glow** → low edge energy → low score.
- **Nothing visible on the background** → subject isolation is working correctly.

The Focus Mask Controls panel (expand with the chevron next to the toggle) exposes the detection parameters. Any changes you make there are picked up by the **next scoring run**, so you can tune the sensitivity for a particular focal length or subject type and then re-score.

### Focus Mask Controls

| Control | Effect on scoring |
|---------|------------------|
| Blur radius | Pre-smoothing before edge detection — increase for noisy high-ISO files |
| Laplacian strength | Amplification of edge response — increase to separate sharp and soft frames more aggressively |
| Overlay opacity | Visual only — does not affect the score |

---

## Understanding Low Scores

A low score (red badge) typically means one of the following:

**Motion blur** — the shutter speed was too slow to freeze the subject. Common with fast-moving birds at the end of a burst. The Focus Mask will show a diffuse halo rather than sharp feather lines.

**Missed or soft focus** — the autofocus tracked the background, a wing tip, or the wrong subject in a multi-bird frame. The Focus Mask will show strong edges somewhere *other* than the subject centre.

**Small or distant subject** — if Vision cannot reliably detect a salient region (subject occupies less than 3 % of the frame), the scorer falls back to the full frame, which dilutes the score with background. Consider cropping the image or using a tighter focal length.

**High ISO noise** — extreme noise can temporarily boost the score by adding false edges. Increasing the blur radius in Focus Mask Controls before re-scoring reduces this effect.

---

## Tips

- **Score after culling for exposure** — sharpness scoring works independently of exposure. Culling badly exposed frames first keeps the catalog clean and makes the normalised scale more meaningful.
- **Re-score with the aperture filter active** — if you only want to compare your telephoto wildlife shots, set the filter to *Wide* first, then score. The 100 baseline will be the sharpest frame within that aperture range.
- **Use the Focus Mask to validate scores** — before discarding a yellow or red frame, open the zoom window and enable the Focus Mask. Sometimes a compositionally strong frame has a lower score only because the subject was slightly smaller and the scoring area included soft background. Trust your eye on borderline cases.
- **Scores reset when you open a new catalog** — each catalog has its own relative scale. A score of 80 in one session says nothing about a score of 80 in a different session.
