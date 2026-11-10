# RawCull development summary

## People assessment and Burst Review

- Human face close-ups were verified in TestFlight. RawCull caches face geometry and face-local sharpness per source. On 85 RAWs, the controlled blur check lowered the sharpness score for all 96 measurable face crops. This established the direction of the metric under blur. Keeper agreement on real bursts remains unmeasured.
- **People preview** is available in AppStore builds. It evaluates the entire open burst and requires at least two frames, one measurable face per frame, compatible cached evidence, and confirmation that the same person appears at a comparable scale. It uses face detail to adjust the baseline order. Only the first two frames in Best frame order can become the proposed winner. **Apply People ranking** changes the displayed order, and **Restore Best frame order** restores it. Missing evidence keeps the baseline. Saved ratings, manual winners, and one-click culling eligibility are unchanged.
- The unsigned AppStore build passed. The offline evaluator passed synthetic checks for winner changes and fallback. On two real group pairs, it retained the input order for a large change in face scale and kept the preferred frame first for a comparable pair where both frames were acceptable. The comparable pair used filename order, so it provides no measurement of improvement over **Best frame**.
- Group ranking remains offline and relies on manually matched faces. Eye-state warnings and a model fallback remain deferred. Wildlife close-ups are experimental inspection aids and are outside People ranking.

## Catalog performance

- Progress publication coalescing reduced sampled main-thread work during preload by 28–34% in two cold app captures. Adding a simpler progress animation reduced sampled weight by about 72% versus the original capture. The final combined capture was only 1.7% faster in elapsed preload time. Smoother interaction and repeatable end-to-end speedups remain unverified.
- The historical 809-ARW benchmark measured empty-thumbnail-cache preload at 8.206 s before and 8.415 s in the final reference. Warm preload was 3.553 s and 3.647 s respectively. The harness fingerprints differed, so these are descriptive comparisons. Source-load wrapper times and resource use varied across runs.
- JPEG option reuse showed no repeatable gain. Direct ImageIO grid downsampling was about 3% slower in diagnostic trials. Source-load instrumentation located long waits within the parser round trip. The interactive trace recorded 31 hitches and no detected hangs over 250 ms. Its worst hitch was predominantly native picker waiting. The retained production changes were limited to progress handling.

## RAW 9 zoom previews

- Fit-to-window uses a bounded direct RAW preview when a developed JPEG is unavailable. Native zoom retains the developed JPEG path. Exposure and clipping inspection uses native resolution, and completed previews share a 256 MiB memory cache.
- Across six ARWs and three passes per mode, median uncached fit delivery at 3072 pixels was 1.418 s versus 4.382 s for the legacy native JPEG path. Process peak RSS was 391 MiB versus 919 MiB. Native delivery remained about 4.4 s. These were standalone image-delivery measurements. GUI first paint and other camera cohorts were outside the measurement.
- Geometry and exposure checks passed on all six files. The focused suite passed 32 tests. The historical full run executed 696 tests with three pre-existing failures involving version metadata and a zoom source expectation.

## Model delivery and test coverage

- CLIP, SAM 3, and Qwen on-demand macOS asset packs were packaged, evaluated, and uploaded without reported errors or warnings for the original App Store migration. The maintainer reported all three available in RawCull 3.2.4. AppStore builds use Apple hosting, and ordinary Release builds use self-hosted delivery.
- Test coverage includes culling and burst state, image sources and caches, preview rendering, AI integration, model provenance, and release metadata. Smoke and performance selectors are defined in the Makefile. Installed-model probes require opt-in inputs. Historical results apply to their recorded builds and workloads.

## Possible next development

- Finish TestFlight checks for applying and restoring People ranking and for its fallback alerts. If more comparable portraits become available, compare keeper choices against RawCull’s actual **Best frame** order before promoting the ranking.
- Revisit group ranking or eye-state warnings if representative labeled bursts become available. Group ranking needs validated face matching. An eye model needs licensed artifacts and separate accuracy and deployment checks.
- If catalog browsing shows visible pauses, capture matched runs and isolate the source-load tail before changing the decoder or scheduling. Recheck clean-install model delivery when packaging or hosting changes.

The detailed reports, procedures, and RAW preview measurement JSON are preserved in Git at `54d483d7`. [Tool entry points](../Scripts/README.md)
