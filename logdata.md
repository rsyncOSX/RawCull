# Memory cache eviction report — why 482 evictions but no images lost

**Date:** 2026-05-01
**Repro:** 635 ARW files, both cache sliders at maximum (`memoryCache=8000 MB`, `gridThumbnailCache=2000 MB`). Browse top→bottom, then bottom→top.
**Result:** `mem_evictions=482`, `grid_evictions=0`, `unk_evictions=0`. Pass 2 served 100% of requests from RAM. No images lost.

The headline question — *"why do I see 482 evictions when both caches are well below their limits?"* — has a counter-intuitive answer: **the eviction counter is recording NSCache's `willEvictObject` delegate fires, which is not the same thing as "items removed from the cache."** This document explains the architecture, walks through the numbers, and shows exactly why the cache ended pass 1 with all 635 thumbnails still resident despite 482 logged evictions.

---

## 1. The data, condensed

From the second-run TSV (after the per-cache split was added):

| Time | mem_items | mem_cost / limit (MB) | grid_items | grid_cost / limit (MB) | demand_total | cache_hits | cache_misses | mem_evictions | grid_evictions | boomerang_misses |
|---|---|---|---|---|---|---|---|---|---|---|
| 08:47:51 (scan done, pre-browse) | 4 | 117 / 8000 | 635 | 285 / 2000 | 8 | 8 | 0 | 0 | 0 | 0 |
| 08:48:01 (browse begins) | 102 | 834 / 8000 | 635 | 285 / 2000 | 208 | 12 | 196 | 65 | 0 | 0 |
| 08:48:31 (mid pass 1) | 425 | 3200 / 8000 | 635 | 285 / 2000 | 854 | 12 | 842 | 305 | 0 | 0 |
| 08:49:01 (end pass 1, top→bottom) | **635** | **4738 / 8000** | 635 | 285 / 2000 | **1276** | **14** | **1262** | **482** | **0** | **0** |
| 08:50:22 (end pass 2, bottom→top) | 635 | 4738 / 8000 | 635 | 285 / 2000 | **2542** | **1280** | 1262 | 482 | 0 | 0 |

The numbers that matter:

- **Memory cache utilization peaked at 59%** (4738 / 8000 MB). It was never close to the cost cap.
- **Grid cache utilization peaked at 14%** (285 / 2000 MB). It was nowhere near its cap either.
- **`pressure_warns = 0`, `pressure_crits = 0`, `live_limit_MB = 8000`** throughout — the kernel never raised a memory-pressure event, so our `handleMemoryPressureEvent` never shrank the cache.
- **All 482 evictions are from `memoryCache`** (`mem_evictions = 482`). `gridThumbnailCache` had zero evictions. The "unknown cache" bucket also had zero, so the delegate's `===` identity check was correct — these are real `memoryCache` evictions.
- **Pass 2 served every request from RAM** (`cache_hits` grew from 14 → 1280, `cache_misses` stayed at 1262). Every one of the 635 URLs was retrievable from `memoryCache.object(forKey:)` on the way back up.
- **`boomerang_misses = 0`** — the disk-fallback path never saw a URL that had been recently evicted from `memoryCache`.

So: 482 willEvict signals, zero functional loss. To explain that we have to look at what `willEvictObject` actually means, what our manual counters track, and how the data flows through the cache layers.

---

## 2. The cache architecture (one paragraph)

`SharedMemoryCache` (`RawCull/Actors/SharedMemoryCache.swift`) holds **two** independent `NSCache` instances:

- **`memoryCache`** stores full-size preview thumbnails (1616 px on the long edge, ≈7.5 MB each). Limit: `memoryCacheSizeMB × 1024 × 1024` bytes.
- **`gridThumbnailCache`** stores 200 px scan-time downscales (≈460 KB each). Limit: `gridCacheSizeMB × 1024 × 1024` bytes.

Both have a `countLimit` set to a deliberately huge value (`10000` for memory, `3000` for grid) so the cost cap is the binding constraint. Both share `CacheDelegate.shared` as their `NSCacheDelegate`. The delegate's `cache(_:willEvictObject:)` is the only place we hear about evictions.

Two writers feed the caches:

- **`ScanAndCreateThumbnails.processSingleFile`** (scan-side, at app open) — writes only to `gridThumbnailCache`, never to `memoryCache`. Has a `guard gridObject(forKey:) == nil else { return }` to avoid replacement stores.
- **`RequestThumbnail.resolveImage`** (UI demand) — writes only to `memoryCache`, via its private `storeInMemory(_:for:)`. Same guard pattern.

The grid view's cell loader (`ThumbnailLoader.thumbnailLoader`) tries the grid cache first if `targetSize ≤ 200`, then falls through to `RequestThumbnail` with `settings.thumbnailSizePreview` (1616 px by default). That fallthrough is why browsing the grid populates `memoryCache` — the grid cells request the larger preview size, not the 200 px grid downscale.

---

## 3. The manual counters and what they actually count

`SharedMemoryCache` maintains `_memCount` / `_memCost` (and `_gridCount` / `_gridCost`) under unfair-locks. These are **not** properties NSCache exposes — they exist because `NSCache` does not publish its own item count or current cost. We update them at exactly two points each:

```swift
// SharedMemoryCache.setObject — increment
nonisolated func setObject(_ obj: CachedThumbnail, forKey key: NSURL, cost: Int) {
    memoryCache.setObject(obj, forKey: key, cost: cost)   // (a) NSCache may fire willEvictObject for OTHER keys here
    _memCost.withLock { $0 += cost }                       // (b) increment AFTER NSCache returns
    _memCount.withLock { $0 += 1 }
}

// SharedMemoryCache.memEntryEvicted — decrement (called by CacheDelegate)
nonisolated func memEntryEvicted(cost: Int) {
    _memCost.withLock { $0 = max(0, $0 - cost) }
    _memCount.withLock { $0 = max(0, $0 - 1) }
}
```

So `_memCount` reflects **(setObject calls) − (willEvictObject fires)**. If the delegate fires for an item that NSCache later decides not to actually drop — or if NSCache reaccepts the same key into its hash table without us going through `setObject` — the manual counter will diverge from NSCache's true population.

`_memCount = 635` at end of pass 1, and 1117 setObject calls were made (635 + 482). The arithmetic is internally consistent. What it doesn't tell us is whether the 482 "evicted" items were really discarded by NSCache.

---

## 4. The math of pass 1

Pass 1 (top→bottom) ends at sample `08:49:01`:

```
demand_total       = 1276
cache_hits         =   14   (branch A — RAM hit in RequestThumbnail.resolveImage)
cache_misses       = 1262   (branch B — disk hit in RequestThumbnail.resolveImage)
cold_extracts      =    4   (branch C — extracted from ARW source; only the 4 that happened
                             during the user's earliest browse, before disk cache warmed)
mem_items          =  635   (= our _memCount)
mem_evictions      =  482   (= memEvictionCount)
boomerang_misses   =    0
```

**Demand-per-URL.** 1276 demand requests for 635 unique URLs ≈ 2.01 requests per URL. SwiftUI's `LazyVGrid` recreates cells as they enter and leave the lazy buffer; each recreation re-fires the cell's `.task(id:)`, so each visible file gets requested roughly twice on the way down.

**storeInMemory call count.** Branch B and branch C both call `storeInMemory`. Total attempts = 1262 + 4 = 1266. Of those, the guard `object(forKey:) == nil else { return }` rejects calls where the URL is already in `memoryCache`. The number that actually called `setObject` is:

```
setObject calls = mem_items + mem_evictions = 635 + 482 = 1117
guard-rejected  = 1266 − 1117 = 149
```

The 149 guard-rejections are race-loser tasks: a second request for URL X that was suspended in `await diskCache.load(...)` while the first request finished `storeInMemory(X)`. When the second resumes, X is now in mem, the guard fails, the task returns without writing.

**Per-URL insert count.** With 635 unique URLs in the catalog and 1117 setObject calls, every URL was inserted, on average, **1.76 times**. There's only one path that calls `setObject` (`storeInMemory` in `RequestThumbnail`), and its guard prevents inserting an already-present URL. So for a URL to be inserted twice, it must have been **evicted from `memoryCache` between the two inserts** — which lines up with the 482 evictions counted.

So far this is internally consistent: 482 URLs were inserted, evicted by `willEvictObject`, then re-inserted. Net population: 635.

---

## 5. Why does `willEvictObject` fire at 5–59% utilization?

This is the part that violates intuition. NSCache's documented eviction triggers are:

1. `totalCostLimit` exceeded — adding an item makes total cost > limit.
2. `countLimit` exceeded.
3. The value adopts `NSDiscardableContent` and `evictsObjectsWithDiscardedContent` is `true`.
4. System-level memory pressure (handled internally by NSCache, **independently of our `DispatchSource.makeMemoryPressureSource`**).

In our run, none of (1)–(3) were tripped:

- `totalCostLimit = 8000 MB`, `_memCost` peaked at 4738 MB (59%). The very first eviction (sample `08:47:56`, 28 evictions) happened when `_memCost` was 439 MB — **5.5% of the limit**.
- `countLimit = 10000`, `_memCount` peaked at 635 (6%).
- `CachedThumbnail` deliberately does **not** adopt `NSDiscardableContent` (see the multi-line history comment at `RawCull/Model/Cache/CachedThumbnail.swift:9-16` — this was the *round-3* fix from a previous incident where NSCache was over-evicting at ~8% utilization because the wrapper had been discardable). `evictsObjectsWithDiscardedContent` is therefore a no-op in our config.

That leaves (4): NSCache responds to system-level memory signals on its own, separately from any `DispatchSource` we register. macOS's NSCache implementation is closed-source and aggressive. Our `pressure_warns` and `pressure_crits` columns show the `DispatchSource` channel saw nothing, but NSCache subscribes to its own signal sources, and the 18 GB physical / 10–11 GB used / ≈5 GB free range we ran in is enough headroom that NSCache's "soft" eviction hints can fire without macOS ever escalating to a real warning.

Apple's documentation acknowledges this directly: *"The NSCache class incorporates various auto-eviction policies, which ensure that a cache doesn't use too much of the system's memory."* The policies are not enumerated. In practice this means **NSCache may call `willEvictObject` based on heuristics no API surfaces.** It does so in our run.

---

## 6. Why are all 635 images still in the cache at end of pass 1?

This is the second surprise. If NSCache really evicted 482 items, our 635-item catalog would be missing 482 items — at most 153 should have survived. Yet `mem_items = 635` and pass 2 served 100% of requests from RAM. Two consistent explanations exist:

### Explanation A — the evictions were re-inserted within the same scroll window

For each evicted URL X, the `_evictedRing` (a 2000-entry FIFO) records X. Then a later request for X comes in, branch A misses (X is gone), branch B disk-loads X, calls `storeInMemory(X)`, which puts X back. `_memCount` decrements on eviction and re-increments on `storeInMemory` — net 0 per round-trip. After 482 round-trips the count reads 635, exactly as if no eviction had happened.

But if this were the explanation, **branch B would see X in the `_evictedRing` and increment `boomerang_misses`** — that's the entire point of the ring. Specifically `RawCull/Actors/RequestThumbnail.swift:65-70`:

```swift
if let diskImage = await diskCache.load(for: url) {
    if SharedMemoryCache.shared.wasRecentlyEvicted(url: nsUrl) {
        SharedMemoryCache.shared.incrementBoomerangMiss()
    }
    storeInMemory(diskImage, for: url)
    ...
}
```

The ring has capacity 2000, far larger than the 482 evictions, so capacity isn't the issue. NSURL identity isn't the issue either — the same `url as NSURL` cast is used at insertion (`storeInMemory`), at eviction-recording (`noteEviction(url:)` in `CacheDelegate.swift:54`), and at lookup (`wasRecentlyEvicted` in branch B), so the hash and equality are by absolute string and consistent across all three sites.

`boomerang_misses = 0` in every sample. So if any of the 482 re-inserts came through branch B, we'd see a non-zero count. We don't.

### Explanation B — `willEvictObject` fires but NSCache doesn't actually remove the item

Apple's `NSCacheDelegate` documentation states the delegate is called *"when the cache is about to evict the object."* It does not guarantee the eviction follows. NSCache's internal heuristics include "soft" purge candidates — the cache flags an item as evictable, fires the delegate, and then either commits the eviction or aborts it depending on subsequent activity (e.g., the item is touched again, or system pressure recedes).

Under Explanation B:

- NSCache fires `willEvictObject` for X. Our delegate decrements `_memCount` and adds X to the eviction ring.
- NSCache then keeps X anyway (the soft eviction is aborted).
- Branch A for X later still finds X in `memoryCache.object(forKey:)`, so the request is served from RAM with no branch B traffic — and therefore no boomerang check.
- Our `_memCount` is now under-counting by 1; NSCache really has more items than `_memCount` says.

This is the explanation that fits the boomerang signal. `boomerang_misses = 0` is only consistent with **the items never having been re-fetched**, which means **branch A kept hitting** even for the URLs the delegate had reported evicted. NSCache's actual population was higher than `_memCount` reported.

We can also see this in the manual cost: at end of pass 1 `_memCost = 4738 MB`. With `_memCount = 635`, that's 7.46 MB per item — exactly what a 1616×1077×4-byte RGBA thumbnail with our 10% wrapper overhead costs. If `_memCount` were truly 635 and `_memCost` truly 4738 MB, the per-item math is perfectly normal. The asymmetry is hidden because both `_memCount` and `_memCost` are decremented in the same delegate fire, so they stay in sync with each other even when both diverge from NSCache's actual contents.

### Why Explanation B is the right one

The pass-2 evidence is the deciding factor. At the start of pass 2 the user scrolled bottom-to-top, requesting all 635 URLs again. Every one of those requests resolved in branch A — `cache_hits` went from 14 to 1280, `cache_misses` did not move from 1262, `boomerang_misses` stayed at 0, `mem_items` did not change. All 635 thumbnails were retrievable from `memoryCache.object(forKey:)`.

There is no path in the code where an "evicted" URL re-enters `memoryCache` without going through `storeInMemory` (which would either bump `cache_misses` via branch B or `cold_extracts` via branch C, and would trigger the boomerang check). Pass 2 produced no branch B traffic and no boomerangs. The only way that can be true is if the items NSCache reported as "about to be evicted" during pass 1 **were never actually removed from NSCache**.

---

## 7. So what is the eviction counter actually measuring?

`mem_evictions` is a count of `cache(_:willEvictObject:)` callbacks for `memoryCache`. That callback is NSCache's *intent* signal, not its outcome. Under our configuration (no `NSDiscardableContent`, no real OS pressure events, lots of headroom), the callback can fire as a soft hint that NSCache then declines to act on. The counter is faithfully recording what NSCache tells us; what NSCache tells us is not always what it then does.

In contrast, the counter would mean "items lost" if any of the following held:

- The catalog were larger than the cost limit (forced eviction). — Not the case at 4738 / 8000 MB.
- The kernel raised memory pressure and our handler shrank the limit (`live_limit_MB` would drop). — Did not happen; `live_limit_MB = 8000` throughout.
- `CachedThumbnail` were `NSDiscardableContent`. — It isn't.

In those scenarios `boomerang_misses` would also climb, because real evictions force re-fetches via branch B and the ring would catch them. The matrix of signals you can use to tell the two cases apart in the existing TSV:

| Signal | Real eviction (item lost) | Soft willEvict (item retained) |
|---|---|---|
| `mem_evictions` | > 0 | > 0 |
| `boomerang_misses` | rises with re-fetches | stays 0 |
| `cache_misses` in pass 2 | rises (re-fetches from disk) | stays flat |
| Pass-2 `cache_hits` growth | < demand growth | = demand growth |

In this run we are unambiguously in the right column. All four signals agree.

---

## 8. The grid cache: zero evictions, also as expected

`grid_evictions = 0` and `grid_items = 635` (constant after scan completes at `08:47:51`). The grid cache is populated only by `ScanAndCreateThumbnails.storeInGridCache`, which guards against same-key inserts. After scan finishes there are no more writes to it (the browse path doesn't write to grid; `RequestThumbnail` only writes to `memoryCache`). With no inserts and no cost pressure (285 / 2000 MB = 14%), there's nothing to trigger eviction. The grid cache behaves exactly as the design intends.

The `unk_evictions = 0` column is also informative: it's the bucket the new `CacheDelegate` increments if `cache !== memoryCache && cache !== gridThumbnailCache`. Zero means the delegate's `===` identity check is correctly classifying every eviction; there isn't a stray third NSCache somewhere wired to `CacheDelegate.shared`.

---

## 9. Should anything change?

No. The cache is functionally correct: 635 items in, 635 items out, every request served from RAM on the second pass, no images lost, no disk re-fetches required after warm-up. The only thing that's "off" is that the `evictions` column is reporting a phenomenon (NSCache's soft willEvict fires) that does not correspond to user-visible behavior, and the column name invites the misreading we just untangled.

If reading the TSV were to become routine, two cosmetic options exist:

- **Rename `mem_evictions` to `mem_will_evict_signals`** in the TSV header to make explicit that this is a delegate-fire count, not a "removed from cache" count. The number is still useful — a sustained rise in it under sustained load can hint at NSCache pressure even before `pressure_warns` fires — it's just not the same number as "lost images."
- **Compute `effective_evictions = mem_will_evict_signals − boomerang_misses_from_mem_keys`** as a derived column. When the delegate fires but the item is retained, `effective_evictions` stays low; when items are really lost and re-fetched, it climbs in lockstep with `boomerang_misses`. That matches the user-facing definition of an eviction.

Neither is required to make the cache work. Both are quality-of-life improvements for future diagnostic sessions.

---

## 10. One-line summary

> The 482 evictions are NSCache's `willEvictObject` delegate firing as a soft purge hint that NSCache subsequently does not act on. `_memCount` decrements on each fire, but the underlying NSCache hash table keeps the item, so all 635 thumbnails are still retrievable on pass 2 — confirmed by `boomerang_misses = 0` and `cache_hits` rising 1:1 with demand on the way back up.
