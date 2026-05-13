# Memory and Cache Diagnostics Checklist

Use this checklist during v1.7.5 release validation to turn the Memory Console TSV into a repeatable answer about cache behavior on a real catalog.

## Scenario

1. Start RawCull from a known cache state. Prefer a cold run after clearing thumbnail caches, or record that the run used warm disk cache.
2. Open Diagnostics -> Memory Console before selecting the catalog. Leave the window open for the whole run.
3. Scan a catalog with at least 500 ARW or NEF files.
4. While thumbnail preload is still active, browse the grid and rated grid enough to force interactive thumbnail requests.
5. Open several large previews or zoom views.
6. Wait until scanning and visible thumbnail activity settle for at least 30 seconds.
7. Use Copy All in the Memory Console and save the TSV with the release validation notes.

Record the catalog size, raw format mix, memory-cache settings, grid-cache settings, whether disk cache was cold or warm, and the approximate actions taken during browsing.

## Signals

- `true_hit_rate_pct`: primary RAM effectiveness signal. This is RAM hits divided by all demand requests, including cold extractions.
- `cold_rate_pct`: source-file extraction pressure. A high value during first scan is expected on cold cache, but it should stop rising quickly once browsing revisits already processed files.
- `hit_rate_pct`: layer-relative RAM versus disk hit rate. Keep it for continuity, but do not use it as the primary health signal because it excludes cold extractions.
- `boomerang_misses`: recently evicted RAM items that were requested again and served from disk. Growth during grid browsing suggests scan/preload work is evicting useful UI thumbnails.
- `pressure_warns` and `pressure_crits`: cumulative memory-pressure events. These catch pressure flicker that may happen between 5-second samples.
- `live_limit_MB`: live NSCache cost limit after pressure handling. Compare it with `mem_limit_MB`; a lower live limit shows pressure-driven shrinkage.
- `mem_evictions`, `grid_evictions`, and `unk_evictions`: eviction source. `unk_evictions` should remain 0.
- `app_MB`, `headroom_MB`, `mem_cost_MB`, and `grid_cost_MB`: memory plateau behavior. After scanning settles, app memory and cache costs should stabilize instead of climbing continuously.

## Interpretation

Treat the run as healthy when:

- `pressure_crits` remains 0.
- `unk_evictions` remains 0.
- `boomerang_misses` stays flat or grows only slightly during interactive browsing.
- `app_MB` plateaus after scan and browsing settle.
- `mem_cost_MB` and `grid_cost_MB` stay under their live/configured limits.
- `live_limit_MB` is not stuck far below `mem_limit_MB` after pressure returns to normal.

Treat the run as concerning when:

- `pressure_crits` increments repeatedly during normal scan or browsing.
- `boomerang_misses` keeps growing while revisiting visible grid items.
- `unk_evictions` is non-zero.
- `live_limit_MB` remains far below `mem_limit_MB` after the workload settles.
- `app_MB` continues climbing after scanning and visible thumbnail activity have stopped.
- `cold_rate_pct` keeps rising during repeated browsing of already processed files.

## Release Note Summary

Summarize the result in one sentence in the v1.7.5 validation notes:

- "Memory diagnostics were stable on a <file-count> file <format> catalog: no critical pressure, no unknown evictions, and app memory plateaued after scan."
- "Memory diagnostics improved but remain watch-listed: <specific signal> still rose during <scenario>."
- "Memory diagnostics remain a known issue: <specific signal> indicates <observed behavior>."
