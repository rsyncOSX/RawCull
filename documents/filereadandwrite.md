# RawCull File Read and Write Reference

This document describes the files RawCull reads and writes, where they are stored on disk, when the operations happen, and where the relevant source code lives.

## Summary

RawCull writes three broad categories of files:

1. App metadata in `~/Library/Application Support/RawCull/`
2. Performance caches in `~/Library/Caches/no.blogspot.RawCull/`
3. User-visible output files, either beside the RAW files or in a copy destination chosen by the user

The important distinction is that RawCull's JSON files and cache JPEGs are app support data, not your photo originals. The only user photo folders RawCull writes into are:

- The RAW folder, when the explicit "Extract JPGs" action saves `.jpg` files beside `.ARW` files.
- The destination folder selected in the Copy UI, when `rsync` copies selected/rated RAW files.

## Culling, Ratings, Scores, and Burst Overrides

### Disk Location

`~/Library/Application Support/RawCull/savedfiles.json`

### What Is Stored

This JSON file stores RawCull's culling state:

- Catalog folder URL
- File names in that catalog
- Date tagged
- Rating
- Sharpness score
- Saliency subject
- Burst winner overrides

It does not store image data.

The stored types are defined in `RawCull/Model/JSON/SavedFiles.swift`.

### Write Path

The write path is built in `WriteSavedFilesJSON.savePath`:

- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:15` sets the file name to `savedfiles.json`.
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:22` gets the user Application Support folder.
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:24` appends the `RawCull` app folder.
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:25` appends `savedfiles.json`.

The file is written here:

- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:51` creates the parent directory.
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:56` writes the JSON atomically.

Encoding happens here:

- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:66` starts JSON encoding.
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:69` encodes the `[SavedFiles]` array.
- `RawCull/Model/JSON/WriteSavedFilesJSON.swift:70` passes the encoded data to the disk writer.

### When It Is Written

`CullingModel` schedules a save after culling state changes. It debounces writes by `350_000_000` nanoseconds, about 0.35 seconds, so a burst of rating changes does not write the file for every single key press.

Relevant source:

- `RawCull/Model/ViewModels/CullingModel.swift:20` sets the default save delay.
- `RawCull/Model/ViewModels/CullingModel.swift:21` uses `WriteSavedFilesJSON.write` as the default save handler.
- `RawCull/Model/ViewModels/CullingModel.swift:154` starts `scheduleSave()`.
- `RawCull/Model/ViewModels/CullingModel.swift:159` cancels any previous pending save.
- `RawCull/Model/ViewModels/CullingModel.swift:162` waits for the debounce delay.
- `RawCull/Model/ViewModels/CullingModel.swift:167` writes the saved snapshot.

Save-triggering changes include:

- Resetting one catalog's saved files: `RawCull/Model/ViewModels/CullingModel.swift:35`
- Resetting all saved files: `RawCull/Model/ViewModels/CullingModel.swift:43`
- Updating one or more ratings: `RawCull/Model/ViewModels/CullingModel.swift:64` and `RawCull/Model/ViewModels/CullingModel.swift:68`
- Applying many ratings at once, for example from sharpness thresholding: `RawCull/Model/ViewModels/CullingModel.swift:84`
- Merging sharpness/saliency results: `RawCull/Model/ViewModels/CullingModel.swift:100`
- Saving burst winner overrides: `RawCull/Model/ViewModels/CullingModel.swift:117`
- Pruning stale burst overrides: `RawCull/Model/ViewModels/CullingModel.swift:145`

The main view model calls these through culling helpers:

- `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift:59` updates one file rating.
- `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift:65` updates multiple file ratings.
- `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift:72` clears the current catalog culling state.
- `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift:80` applies sharpness threshold ratings.

### Read Path

The read path is built in `ReadSavedFilesJSON.savePath`:

- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:21` sets the file name to `savedfiles.json`.
- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:28` gets the user Application Support folder.
- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:30` appends the `RawCull` app folder.
- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:31` appends `savedfiles.json`.

The file is read here:

- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:39` checks whether the file exists.
- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:46` decodes the JSON array from disk.
- `RawCull/Model/JSON/ReadSavedFilesJSON.swift:49` maps decoded records to `SavedFiles`.

### When It Is Read

RawCull reads saved culling state after a catalog has been scanned and files have been loaded:

- `RawCull/Model/ViewModels/CullingModel.swift:29` loads saved files into memory.
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:117` marks scanning done.
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:118` calls `cullingModel.loadSavedFiles()`.
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:120` rebuilds the current catalog rating cache.
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:121` loads persisted scoring/saliency into the sharpness model.

## App Settings

### Disk Location

`~/Library/Application Support/RawCull/settings.json`

### What Is Stored

This JSON file stores RawCull preferences:

- Memory cache size
- Grid cache size
- Grid, preview, and full-size thumbnail sizes
- Thumbnail sharpening settings
- Score and saliency badge settings
- Sharpness scoring settings
- Focus mask settings

### Write Path

The settings path is built in `SettingsViewModel.settingsURL`:

- `RawCull/Model/ViewModels/SettingsViewModel.swift:100` sets the file name to `settings.json`.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:107` gets the user Application Support folder.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:109` appends the `RawCull` app folder.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:110` appends `settings.json`.

The file is written by `saveSettings()`:

- `RawCull/Model/ViewModels/SettingsViewModel.swift:170` starts `saveSettings()`.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:179` creates the `SavedSettings` value.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:202` creates the JSON encoder.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:204` encodes settings.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:208` moves directory creation and writing to a background task.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:209` creates the parent directory.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:214` writes the file atomically.

### When It Is Written

Settings are written when the settings UI or toolbar toggles call `saveSettings()`. Examples:

- Cache settings save/reset actions call save from `RawCull/Views/Settings/CacheSettingsTab.swift`.
- Thumbnail settings save/reset/toggle actions call save from `RawCull/Views/Settings/ThumbnailSizesTab.swift`.
- Focus settings save/reset actions call save from `RawCull/Views/Settings/FocusSettingsTab.swift`.
- Score and saliency toolbar toggles call save from `RawCull/Views/RawCullSidebarMainView/SharedMainToolbarContent.swift`.

### Read Path and Timing

The file is read by `loadSettings()`:

- `RawCull/Model/ViewModels/SettingsViewModel.swift:116` starts loading.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:122` creates the parent directory if missing.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:129` uses defaults if the file does not exist.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:134` reads file data in a utility-priority detached task.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:138` decodes `SavedSettings`.
- `RawCull/Model/ViewModels/SettingsViewModel.swift:140` applies decoded values to the observable model.

Other code reads settings snapshots through `SettingsViewModel.shared.asyncgetsettings()`. For example:

- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:129` reads settings to determine thumbnail preload size.
- `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift:71` waits for settings before applying stored scoring settings.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:49` reads settings before thumbnail preload work.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:26` reads settings for zoom thumbnail behavior.

## Thumbnail Disk Cache

### Disk Location

`~/Library/Caches/no.blogspot.RawCull/Thumbnails/`

### What Is Stored

This folder contains JPEG thumbnail cache files used for fast grid and preview loading. File names are MD5 hashes of the source file's standardized path, not the original photo names.

Example shape:

`~/Library/Caches/no.blogspot.RawCull/Thumbnails/<md5>.jpg`

These files are cache data. Deleting them is safe; RawCull can recreate them from the original RAW files.

### Path and File Name Logic

The cache directory is created in `DiskCacheManager`:

- `RawCull/Actors/DiskCacheManager.swift:15` gets the user Caches folder.
- `RawCull/Actors/DiskCacheManager.swift:16` appends `no.blogspot.RawCull/Thumbnails`.
- `RawCull/Actors/DiskCacheManager.swift:20` creates the directory.

The cache file URL is derived here:

- `RawCull/Actors/DiskCacheManager.swift:34` starts `cacheURL(for:)`.
- `RawCull/Actors/DiskCacheManager.swift:35` uses the source URL's standardized path.
- `RawCull/Actors/DiskCacheManager.swift:37` hashes that path with MD5.
- `RawCull/Actors/DiskCacheManager.swift:39` appends `.jpg`.

### Write Path

The actual disk write happens here:

- `RawCull/Actors/DiskCacheManager.swift:56` starts `save(_:for:)`.
- `RawCull/Actors/DiskCacheManager.swift:57` resolves the hashed cache file URL.
- `RawCull/Actors/DiskCacheManager.swift:62` writes JPEG data atomically.

JPEG encoding happens here:

- `RawCull/Actors/DiskCacheManager.swift:74` starts `jpegData(from:)`.
- `RawCull/Actors/DiskCacheManager.swift:83` uses JPEG quality `0.7`.

### When It Is Written

Thumbnail cache files are written when RawCull has to extract a thumbnail from a source RAW file.

During catalog preload:

- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:155` creates `ScanAndCreateThumbnails`.
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:160` starts the preload task.
- `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:161` calls `preloadCatalog`.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:89` discovers files in the catalog.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:123` processes one source file.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:141` checks disk cache before extraction.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:155` begins extraction from source when cache is missing.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:189` encodes the extracted thumbnail to JPEG.
- `RawCull/Actors/ScanAndCreateThumbnails.swift:196` saves it through `DiskCacheManager`.

During UI-driven thumbnail requests:

- `RawCull/Actors/RequestThumbnail.swift:40` starts a thumbnail request.
- `RawCull/Actors/RequestThumbnail.swift:60` checks RAM cache.
- `RawCull/Actors/RequestThumbnail.swift:68` checks disk cache.
- `RawCull/Actors/RequestThumbnail.swift:82` extracts from source if both caches miss.
- `RawCull/Actors/RequestThumbnail.swift:107` encodes the extracted thumbnail.
- `RawCull/Actors/RequestThumbnail.swift:112` saves it through `DiskCacheManager`.

### Read Path

The thumbnail cache is read here:

- `RawCull/Actors/DiskCacheManager.swift:42` starts `load(for:)`.
- `RawCull/Actors/DiskCacheManager.swift:43` resolves the hashed cache file URL.
- `RawCull/Actors/DiskCacheManager.swift:46` reads data from disk.
- `RawCull/Actors/DiskCacheManager.swift:47` creates an `NSImage`.

Callers include:

- `RawCull/Actors/ScanAndCreateThumbnails.swift:142` during catalog preload.
- `RawCull/Actors/RequestThumbnail.swift:69` during UI thumbnail requests.

### Cache Utilities

Disk cache size and pruning are also implemented in `DiskCacheManager`:

- `RawCull/Actors/DiskCacheManager.swift:91` computes total disk cache size.
- `RawCull/Actors/DiskCacheManager.swift:119` prunes old cache files.
- `RawCull/Actors/DiskCacheManager.swift:138` removes expired cache files.

## Full-Size JPEG Preview Cache

### Disk Location

`~/Library/Caches/no.blogspot.RawCull/FullsizeJPGs/`

### What Is Stored

This folder contains larger JPEG preview cache files extracted from RAW files. RawCull uses these for zoom and comparison views so it does not have to re-extract the embedded JPEG every time.

These are still cache files. They are not the same as user-visible extracted sidecar `.jpg` files.

### Path and File Name Logic

The cache directory is created in `FullSizeJPGDiskCache`:

- `RawCull/Actors/FullSizeJPGDiskCache.swift:16` gets the user Caches folder.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:17` appends `no.blogspot.RawCull/FullsizeJPGs`.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:21` creates the directory.

The cache file URL is derived here:

- `RawCull/Actors/FullSizeJPGDiskCache.swift:27` starts `cacheURL(for:)`.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:29` hashes a version string plus the source path.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:32` appends `.jpg`.

### Write Path

The actual disk write happens here:

- `RawCull/Actors/FullSizeJPGDiskCache.swift:64` starts `save(_:for:)`.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:65` resolves the hashed cache file URL.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:69` writes JPEG data atomically.

JPEG encoding happens here:

- `RawCull/Actors/FullSizeJPGDiskCache.swift:79` starts `jpegData(from:)`.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:88` uses JPEG quality `0.85`.

### When It Is Written

The full-size cache is written in two main situations.

First, when zoom or comparison needs a full preview and no sidecar/cached image exists:

- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:61` builds the RAW URL.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:62` builds a sidecar `.jpg` URL beside the RAW.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:75` tries to load the sidecar `.jpg` first.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:89` tries to load the full-size cache.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:101` extracts the embedded JPEG from the RAW if needed.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:110` encodes the extracted image.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:111` saves it to the full-size cache.

Second, when the user chooses "Create JPG Disk Cache":

- `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift:29` starts `startScanAndExtractJPGs()`.
- `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift:51` creates `ScanAndExtractJPGs`.
- `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift:56` calls `extractCatalogJPGs()`.
- `RawCull/Actors/ScanAndExtractJPGs.swift:39` starts catalog extraction.
- `RawCull/Actors/ScanAndExtractJPGs.swift:80` skips files already in the full-size cache.
- `RawCull/Actors/ScanAndExtractJPGs.swift:96` extracts an embedded JPEG from the RAW.
- `RawCull/Actors/ScanAndExtractJPGs.swift:105` encodes it for the cache.
- `RawCull/Actors/ScanAndExtractJPGs.swift:112` saves it to the full-size cache.

### Read Path

The full-size cache is read here:

- `RawCull/Actors/FullSizeJPGDiskCache.swift:35` checks whether a cache file exists.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:47` starts loading a cached image.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:52` opens the cached JPEG through ImageIO.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:56` creates a `CGImage`.

Callers include:

- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:89` for zoom overlays.
- `RawCull/Actors/ScanAndExtractJPGs.swift:80` when warming the cache.
- `RawCull/Views/ComparisonGridView/ComparisonImageLoader.swift:49` for comparison image loading.

### Cache Utilities

Disk cache size and pruning are implemented in `FullSizeJPGDiskCache`:

- `RawCull/Actors/FullSizeJPGDiskCache.swift:96` computes total disk cache size.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:124` prunes old cache files.
- `RawCull/Actors/FullSizeJPGDiskCache.swift:143` removes expired cache files.

## User-Visible Extracted JPEG Sidecars

### Disk Location

Next to each source RAW file.

Example:

- Source RAW: `/Some/Catalog/_DSC1234.ARW`
- Extracted JPEG: `/Some/Catalog/_DSC1234.jpg`

### What Is Stored

These are JPEG image files extracted from the RAW's embedded preview. Unlike cache files, they are written directly into the user's photo folder and keep the original photo base name.

### Write Path

The sidecar output path is built and written in `SaveJPGImage`:

- `RawCull/Actors/SaveJPGImage.swift:18` starts `save(_:originalURL:)`.
- `RawCull/Actors/SaveJPGImage.swift:19` replaces the original extension with `.jpg`.
- `RawCull/Actors/SaveJPGImage.swift:25` writes the JPEG atomically.

JPEG encoding happens here:

- `RawCull/Actors/SaveJPGImage.swift:36` starts `jpegData(from:)`.
- `RawCull/Actors/SaveJPGImage.swift:48` uses JPEG quality `1.0`.

### When It Is Written

The explicit "Extract JPGs" action creates these files:

- `RawCull/Views/RawCullSidebarMainView/RawCullMainView.swift:113` shows the Extract action in the alert.
- `RawCull/Views/RawCullSidebarMainView/extension+RawCullView.swift:32` starts `extractFilteredFilesJPGS()`.
- `RawCull/Views/RawCullSidebarMainView/extension+RawCullView.swift:47` creates `ExtractAndSaveJPGs` from `viewModel.filteredFiles`.
- `RawCull/Views/RawCullSidebarMainView/extension+RawCullView.swift:51` calls `extractAndSavejpgs()`.
- `RawCull/Actors/ExtractAndSaveJPGs.swift:29` stores the selected/filtered source file URLs.
- `RawCull/Actors/ExtractAndSaveJPGs.swift:40` starts `extractAndSavejpgs()`.
- `RawCull/Actors/ExtractAndSaveJPGs.swift:82` processes one RAW file.
- `RawCull/Actors/ExtractAndSaveJPGs.swift:86` extracts the embedded JPEG from the RAW.
- `RawCull/Actors/ExtractAndSaveJPGs.swift:89` encodes the JPEG.
- `RawCull/Actors/ExtractAndSaveJPGs.swift:91` saves the sidecar `.jpg` beside the RAW.

### Read Path

RawCull can read these sidecar JPEG files later when zooming/comparing, before it falls back to the full-size cache or re-extraction:

- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:62` builds the sidecar `.jpg` URL.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:75` tries to load the sidecar JPEG.
- `RawCull/Model/Handlers/ZoomPreviewHandler.swift:81` uses it if present.
- `RawCull/Views/ComparisonGridView/ComparisonImageLoader.swift:40` builds the sidecar `.jpg` URL for comparison images.
- `RawCull/Views/ComparisonGridView/ComparisonImageLoader.swift:43` tries to load the sidecar JPEG for comparison images.

## Copy Feature and Rsync Include File

### Include File Disk Location

`~/Documents/copyfilelist.txt`

### What Is Stored

This is a temporary-ish include list for `rsync`. It contains one file name per line, based on the files RawCull is about to copy.

It does not contain image data.

### Write Path

The path is built in `ExecuteCopyFiles`:

- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:24` sets the file name to `copyfilelist.txt`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:26` gets the user Documents folder.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:27` appends `copyfilelist.txt`.

The include file is written here:

- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:103` handles the "copy tagged files" case.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:106` writes tagged file names.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:112` handles the "copy rated files" case.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:114` writes rated file names.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:229` starts `writeincludefilelist`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:230` joins file names with newlines.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:235` writes the include file atomically.

The include file is passed to `rsync` here:

- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:65` builds `--include-from=<path>`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:66` appends it to the rsync arguments.

### When It Is Written

It is written when the user starts a copy operation from the Copy UI:

- `RawCull/Views/CopyFiles/CopyFilesView.swift:121` starts `executeCopyFiles()`.
- `RawCull/Views/CopyFiles/CopyFilesView.swift:124` creates `ExecuteCopyFiles`.
- `RawCull/Views/CopyFiles/CopyFilesView.swift:136` calls `startcopyfiles`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:52` starts `startcopyfiles`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:100` begins the include-file write section.

### Actual Copied RAW Files

The actual RAW files are copied by `rsync` from the selected source folder to the selected destination folder:

- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:79` resolves the source folder.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:86` resolves the destination folder.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:94` appends the source path to rsync arguments.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:95` appends the destination path to rsync arguments.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:121` creates the rsync process.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:129` executes the process.

In dry-run mode, the copy is simulated and files are not copied.

## Source and Destination Folder Bookmarks

### Disk Location

Stored in macOS `UserDefaults`, not as normal visible files in the project or photo folders.

Keys:

- `sourceBookmark`
- `destBookmark`

### What Is Stored

Security-scoped bookmark data for the source and destination folders. This lets the sandboxed app regain access to those folders later.

### Write Path

Bookmarks are created when the user selects source/destination folders:

- `RawCull/Views/CopyFiles/OpencatalogView.swift:23` presents the file importer.
- `RawCull/Views/CopyFiles/OpencatalogView.swift:32` starts security-scoped access.
- `RawCull/Views/CopyFiles/OpencatalogView.swift:39` creates bookmark data.
- `RawCull/Views/CopyFiles/OpencatalogView.swift:44` writes the bookmark to `UserDefaults`.
- `RawCull/Views/CopyFiles/SourceAndDestinationSection.swift:25` creates the source folder picker.
- `RawCull/Views/CopyFiles/SourceAndDestinationSection.swift:28` passes `sourceBookmark` as the source key.
- `RawCull/Views/CopyFiles/SourceAndDestinationSection.swift:56` creates the destination folder picker.
- `RawCull/Views/CopyFiles/SourceAndDestinationSection.swift:59` passes `destBookmark` as the destination key.

### Read Path

Bookmarks are read when the copy operation starts:

- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:245` starts `getAccessedURL`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:247` reads bookmark data from `UserDefaults`.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:250` resolves bookmark data into a URL.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:256` starts security-scoped access.
- `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:274` falls back to the plain path if no bookmark is available.

## Quick Table

| File or Folder | Kind | Written When | Read When | Main Source |
|---|---|---|---|---|
| `~/Library/Application Support/RawCull/savedfiles.json` | Culling metadata | Ratings, scoring, burst overrides, clear/reset | After catalog scan | `WriteSavedFilesJSON`, `ReadSavedFilesJSON`, `CullingModel` |
| `~/Library/Application Support/RawCull/settings.json` | App settings | Settings save/toggle/reset | Settings model load and settings snapshots | `SettingsViewModel` |
| `~/Library/Caches/no.blogspot.RawCull/Thumbnails/` | Thumbnail cache | Thumbnail extraction during scan or UI request | Thumbnail scan/request path | `DiskCacheManager`, `ScanAndCreateThumbnails`, `RequestThumbnail` |
| `~/Library/Caches/no.blogspot.RawCull/FullsizeJPGs/` | Full-size JPEG preview cache | Zoom/comparison extraction or "Create JPG Disk Cache" | Zoom/comparison/cache warmup | `FullSizeJPGDiskCache`, `ZoomPreviewHandler`, `ScanAndExtractJPGs` |
| `<RAW folder>/<filename>.jpg` | User-visible extracted JPEG | Explicit "Extract JPGs" action | Zoom/comparison sidecar-first loading | `ExtractAndSaveJPGs`, `SaveJPGImage`, `ZoomPreviewHandler` |
| `~/Documents/copyfilelist.txt` | Rsync include list | Start copy operation | Used by rsync via `--include-from` | `ExecuteCopyFiles` |
| Selected copy destination folder | Copied RAW files | Non-dry-run copy operation | Outside RawCull's persistence model | `ExecuteCopyFiles` |
| `UserDefaults[sourceBookmark]`, `UserDefaults[destBookmark]` | Security bookmarks | Source/destination selection | Start copy operation | `OpencatalogView`, `ExecuteCopyFiles` |
