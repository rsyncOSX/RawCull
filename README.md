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

v1.6.4 — April 24, 2026 — in active development

## Sony ARW compatibility

| Camera Body  | EXIF | FocusPt | Sharpness | Saliency | RAW Types | Dimensions |
|---|---|---|---|---|---|---|
| ILCE-1M2  |  ✅  |  ✅  |  ✅  |  ✅  | Compressed | 4320 × 2880 (12.4 MP, S), 5616 × 3744 (21.0 MP, M), 8640 × 5760 (49.8 MP, L) |
| ILCE-1   |  ✅  |  ✅  | ✅  | ✅  | Compressed | 8640 × 5760 (49.8 MP, L) |
| ILCE-7M5  |  ✅  |  ✅  |  ✅  |  ✅  | Compressed | 7008 × 4672 (32.7 MP, L) |
| ILCE-7RM5  |  ✅  |  ✅  |  ✅  |  ✅  | Compressed | 9504 × 6336 (60.2 MP, L) |
| ILCE-9M3 |  ✅  |  ✅  |  ✅  | ✅  | Compressed | 6000 × 4000 (24.0 MP, L) |

## Nikon NEF body compatibility (experimental)

| Camera Body | EXIF | FocusPt | Sharpness | Saliency | RAW Types | Dimensions |
|---|---|---|---|---|---|---|
| Z9 | ✅ | ❌ | ✅ | ✅ | Compressed | ~8256 × 5504 (45.4 MP, L) |
| Z8 | ✅ | ❌ | ✅ | ✅ | Compressed | ~8256 × 5504 (45.7 MP, L) |
| Z7 / Z7 II | ✅ | ❌ | ✅ | ✅ | Compressed | ~8256 × 5504 (45.7 MP, L) |
| Z6 / Z6 II / Zf | ✅ | ❌ | ✅ | ✅ | Compressed | ~6048 × 4024 (24.3–24.5 MP, L) |

## Documentation

- [User documentation](https://rawcull.netlify.app)
- [Release notes](https://rawcull.netlify.app/blog/)

![](images/rsyncui.png)

Focus mask and focus point applied:

![](images/nomask.png)
![](images/focusmask.png)
