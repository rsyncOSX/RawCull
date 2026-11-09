# People assessment pilot

9 November 2026. Initial Phase 0 feasibility run for [narrative.md](narrative.md).

The local corpus contained 85 originals (63 CR2, 12 CRW, 10 ARW). The standalone Swift harness read ImageIO embedded previews with orientation transforms and ran one worker on macOS 27.2. Each image ran through Vision face detection, landmarks and capture quality, then Core Image face detection with closed-eye flags.

| Maximum preview dimension | Images processed | Images with detections (Vision / Core Image) | Faces (Vision / Core Image) | Core Image closed-eye flags | Median decode / Vision / Core Image | Peak process RSS |
|---|---:|---:|---:|---:|---|---:|
| 1024 px | 85 | 68 / 68 | 101 / 101 | 32 | 14.26 / 7.52 / 10.95 ms | 524 MiB |
| 1600 px | 85 | 65 / 65 | 97 / 97 | 32 | 11.86 / 8.37 / 12.22 ms | 1074 MiB |

Each row represents one sequential run, with 1024 px first. The first run included framework startup. Peak RSS includes the whole harness and its frameworks. The results are unlabelled, and equal counts do not establish agreement on individual faces or eyes. The app's preview path can use RawParserKit, so these decode figures describe the standalone ImageIO path.

Vision failed with an ANE inference-plan error inside the command sandbox. The runs above completed outside that sandbox. CSV rows identify files by zero-based index in path-sorted order and omit filenames.

From the repository root:

```sh
swiftc -module-cache-path /tmp/rawcull-pilot-module-cache -O Scripts/PeopleAssessmentPilot.swift -o /tmp/rawcull-people-pilot
/usr/bin/time -l /tmp/rawcull-people-pilot "$HOME/testphotos" 1024 > /tmp/rawcull-people-1024.csv
/usr/bin/time -l /tmp/rawcull-people-pilot "$HOME/testphotos" 1600 > /tmp/rawcull-people-1600.csv
```

The next Phase 0 pass needs per-eye labels and face correspondence, a landmark-aperture comparator, and repeated one- and two-worker measurements on baseline hardware. Backend selection remains open.

## Per-eye follow-up

The 1024 px run produced 202 eye rows from faces with two Vision eye contours. The aperture heuristic returned a value for 125 rows. It divides contour height by contour width along the contour's longest axis and abstains below eight preview pixels. Core Image supplied 198 associated flags, including 30 closed flags. The other four rows had no usable unique face and eye association. The earlier frame-level count of 32 included flags regardless of correspondence.

Pass a third argument to save the per-eye JSON manifest. Each row includes the original filename, a normalized top-left face box in `[x, y, width, height]` order, and an image-relative eye side. The labeling copy omits both predictions to avoid bias. Fill its `label` fields with `open`, `closed`, or `uncertain`. Leave unreviewed rows null. The manifest samples detected two-eye faces and cannot measure missed faces or single-visible-eye coverage.

## First manual review

The reviewer checked seven deliberately selected photos from the eight-photo review set. Of 20 reviewed eyes, 16 had an open or closed label and four were unassessable behind sunglasses. Core Image agreed with 14 of the 16 visible-eye labels. Its two false closed flags came from one small face with both eyes open and squinting in sunlight. It also flagged both eyes closed behind sunglasses on one face. The other sunglasses face received neither closed flag.

Aperture was narrow on a confirmed open face as well as on confirmed closed eyes. Treat this first review as a set of failure examples. It was selected for difficult cases, and the reviewer saw the predictions. It cannot establish an accuracy rate or an aperture threshold.

The eight selected files now live in the corpus's `test1` subfolder. The harness reads one directory at a time. Use that folder directly to rerun the review set.

The eighth photo confirmed another visibility failure. In `_MG_2102.CR2`, the reviewer could not see the eyes of either right-hand person, and one wore sunglasses. Core Image flagged both eyes closed on one person and neither on the other. All four eyes are labeled unassessable. The left-hand person was looking at the photographer, with eye state unspecified. For `_MG_2040.CR2`, the reviewer confirmed the previously labeled right-hand girl was looking at the photographer. The review now contains 24 eye labels, eight of them unassessable.

## Visibility sweep

All 24 reviewed eyes matched uniquely at both preview limits by filename, image-relative eye side, and face-box intersection-over-union of at least 0.5. The harness now records actual preview dimensions, eye contour width in preview pixels, and Vision yaw and pitch.

| Preview limit | Minimum eye width | Visible eyes retained | Unassessable eyes retained |
|---|---:|---:|---:|
| 1024 px | 8 px | 14 / 16 | 3 / 8 |
| 1024 px | 12 px | 12 / 16 | 2 / 8 |
| 1600 px | 8 px | 14 / 16 | 6 / 8 |
| 1600 px | 12 px | 14 / 16 | 3 / 8 |

A larger preview can move hidden eyes past the same width cutoff. At 1024 px the large sunglasses face produced eye contours about 21 px wide and an absolute yaw estimate of 76°. The other sunglasses face had an absolute yaw estimate of about 8°. A visible face also had an absolute yaw estimate of 52°. Width and pose can support abstention for some cases, but they cannot establish eye visibility on their own. These cutoffs are diagnostic only. The selected review set does not support fitting a production threshold.

The next review samples six previously unreviewed photos across different filenames and face sizes. The photographer receives only filenames and face locations. This checks additional cases without exposing predictions. Independence by shoot or person has yet to be verified.

## Blind follow-up review

Six faces were reviewed with detector suggestions hidden. The reviewer labeled nine eyes open, two closed, and one uncertain. Core Image agreed on 10 of the 11 assessable eyes. Both closed eyes were flagged correctly. The mismatch was an open eye on a small, out-of-focus face that Core Image flagged closed. It also flagged that person's other eye closed, which the reviewer marked uncertain.

An 8 px width gate would have withheld both flags on that small face (4.3 and 5.3 px). It also would have withheld one correctly flagged closed eye on another face (6.2 px). With this gate, nine of the eleven assessable eyes receive a decision, all in agreement, while two assessable eyes and the uncertain eye are withheld. This small follow-up illustrates the coverage cost of the gate. It does not validate a production threshold.

## Confirmation and correction pass

The confirmation export contains 78 of 118 queue entries. The reviewer accepted 47 and rejected 31. Forty entries remain unreviewed. The reviewer then supplied individual eye labels for all 31 rejected entries with suggestions hidden.

Across these 62 eye labels, 23 previously uncertain eyes were labeled open and 11 were labeled closed. Sixteen stayed uncertain. Nine open and two closed proposals matched the corrected labels. One open proposal changed to uncertain because only the other eye was visible. Six face-level corrections matched both original proposals despite the earlier False response. Use the per-eye correction for these entries. The correction set was selected from rejected entries and does not estimate accuracy across the corpus.

On the corrected subset, with the pose cutoff held fixed, reducing the width gate from 8 to 6 px changed the 45 visible-eye labels from 11 correct, zero wrong, and 34 withheld to 27 correct, one wrong, and 17 withheld. Both variants assigned a state to one of the 17 unassessable eyes. This is a retrospective sweep on disagreements. Test the 6 px candidate on fresh blind labels before choosing a threshold.

## Blind width comparison

The reviewer labeled 12 previously unreviewed face crops with suggestions hidden. Of 24 eyes, 20 were open, two closed, and two uncertain. The sample included four faces where the settings could differ and eight comparison faces.

| Minimum eye width | Correct on assessable eyes | Wrong on assessable eyes | Withheld on assessable eyes | Correctly withheld on unassessable eyes |
|---|---:|---:|---:|---:|
| 8 px | 17 | 0 | 5 | 2 |
| 6 px | 20 | 2 | 0 | 2 |

Lowering the gate recovered three correctly identified open eyes, but both closed eyes in one frame were reported open. The 8 px gate withheld both. Keep 8 px as the conservative pilot setting. This batch contained only two closed eyes, both on the same face. It does not support a production eye-state decision. A face-close-up and local-detail milestone can proceed separately from eye-state warnings.

## Face-only TestFlight scope

Phase 1 delivered face geometry and an experimental face-local detail metric. Phase 2 delivered on-demand per-file persistence, with indexing priority and cancellation when navigating away. Phase 3 delivered automatic face close-ups alongside manual inspection. The face-only TestFlight build can exercise that subset. The proposal's broader scheduling and per-eye evidence remain separate work.

A controlled blur check used the current detector on 85 RAWs and ImageIO embedded previews capped at 1600 pixels. It found 110 faces and measured detail on 96. Applying Gaussian blur (sigma 2) lowered the detail score in all 96 measurable crops using the same face boxes. The other 14 faces had no detail score. This checks the direction of the metric under controlled blur. It does not measure keeper agreement across real burst frames.

TestFlight checks for the face-only build:

- Open Close-ups on portraits, group shots, and `_MG_2088.CR2`. Check crop placement and confirm that the two visible faces in that regression case each have a crop.
- Switch quickly between frames, close the panel during detection, and reopen a catalog. Check that no previous frame's crops appear on the newly selected image.
- Compare faces of the same person across real burst frames with compatible preview scale. Record the sharper frame or a tie before comparing scores.
- Check that manual regions, ratings, and burst order stay stable during face detection. Exercise both Best frame and AF-point sharpness sorting.
- Exercise missing JPG previews, including `CRW_6750.CRW`, and use Try RAW to open the alternate source.

Phase 4 starts with measuring agreement on real frame pairs and, if the evidence warrants it, evaluating a people-aware rank in shadow mode. TestFlight feedback on close-ups and local detail does not require any ranking changes.
