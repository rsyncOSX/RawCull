# RawCull

[![GitHub license](https://img.shields.io/github/license/rsyncOSX/RawCull)](https://github.com/rsyncOSX/RawCull/blob/main/Licence.MD)

RawCull is a macOS photo review and culling application for Sony ARW RAW files, built exclusively for Apple Silicon. It combines GPU-accelerated analysis — EXIF extraction, focus point detection, sharpness scoring, and saliency — to help you quickly identify your best shots.

## Requirements

- macOS Sequoia or later
- **Apple Silicon** (M-series) only

## Installation

Install via Homebrew:

```bash
brew tap rsyncOSX/cask && brew install --cask rawcull
```

Or download from the [Apple App Store](https://apps.apple.com/no/app/rawcull/id6759362764?mt=12) or [GitHub Releases](https://github.com/rsyncOSX/RawCull/releases). The GitHub version may appear a day or two ahead of the App Store release due to review timelines.

## Latest release

v1.6.3 — April 23, 2026 — in active development

## Supported Sony bodies

All bodies listed below have been tested for EXIF, focus point, sharpness, and saliency extraction. All files use compressed RAW.

| Camera body | EXIF | Focus point | Sharpness | Saliency | RAW types | Dimensions |
|---|---|---|---|---|---|---|
| ILCE-1 | ✅ | ✅ | ✅ | ✅ | Compressed | 8640 × 5760 (49.8 MP, L) |
| ILCE-1M2 | ✅ | ✅ | ✅ | ✅ | Compressed | 4320 × 2880 (12.4 MP, S), 5616 × 3744 (21.0 MP, M), 8640 × 5760 (49.8 MP, L) |
| ILCE-7M5 | ✅ | ✅ | ✅ | ✅ | Compressed | 7008 × 4672 (32.7 MP, L) |
| ILCE-7RM5 | ✅ | ✅ | ✅ | ⚠️ | Compressed | 9504 × 6336 (60.2 MP, L) |
| ILCE-9M3 | ✅ | ✅ | ✅ | ✅ | Compressed | 6000 × 4000 (24.0 MP, L) |

> ⚠️ ILCE-7RM5 saliency failed on one of three test files. ILCE-7M5 and ILCE-7RM5 support is being expanded — if you can share test ARW files from either body, please get in touch.

## Documentation

- [User documentation](https://rawcull.netlify.app)
- [Release notes](https://rawcull.netlify.app/blog/)

![](images/rsyncui.png)

Focus mask and focus point applied:

![](images/nomask.png)
![](images/focusmask.png)
