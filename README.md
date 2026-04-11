# RawCull

[![GitHub license](https://img.shields.io/github/license/rsyncOSX/RawCull)](https://github.com/rsyncOSX/RawCull/blob/main/Licence.MD)

macOS photo review and selection application for Sony A1 mkI and mkII ARW raw files. This is a build for Apple Silicon only.

## Requirements

- macOS 26 Tahoe and later
- **Apple Silicon** (M-series) only

## Installation

RawCull is available for download on the [Apple App Store](https://apps.apple.com/no/app/rawcull/id6759362764?mt=12) or from the [GitHub Repository](https://github.com/rsyncOSX/RawCull/releases). It is possible that the GitHub version is released a day or two before the Apple App Store release due to the different release processes employed by each platform.

```
brew tap rsyncOSX/cask && brew install --cask rawcull
```

## ARW body compatibility diagnostic

The following Sony bodies successfully extract EXIF, focus points, sharpness, and saliency, except for the ILCE-7RM5, which failed to extract saliency on one of its three files. The ILCE-1M2 is the only body tested across all three Sony RAW size variants (S/M/L). All files use compressed RAW, and every body achieves full-resolution L-size output, ranging from 12.4 MP (ILCE-1M2 S-crop) to 60.2 MP (ILCE-7RM5). The ILCE-7M5 and ILCE-7RM5 are the next bodies to focus on, but I depend on test ARW files to properly test them before officially concluding support for these two bodies.

| Camera Body  | EXIF | FocusPt | Sharpness | Saliency | RAW Types | Dimensions |
|---|---|---|---|---|---|---|
| ILCE-1   |  ✅  |  ✅  | ✅  | ✅  | Compressed | 8640 × 5760 (49.8 MP, L) |
| ILCE-1M2  |  ✅  |  ✅  |  ✅  |  ✅  | Compressed | 4320 × 2880 (12.4 MP, S), 5616 × 3744 (21.0 MP, M), 8640 × 5760 (49.8 MP, L) |
| ILCE-7M5  |  ✅  |  ✅  |  ✅  |  ✅  | Compressed | 7008 × 4672 (32.7 MP, L) |
| ILCE-7RM5  |  ✅  |  ✅  |  ✅  |  ✅  | Compressed | 9504 × 6336 (60.2 MP, L) |
| ILCE-9M3 |  ✅  |  ✅  |  ✅  | ✅  | Compressed | 6000 × 4000 (24.0 MP, L) |

## Version

Current version: v1.4.6 - released April 11, 2026. 

## Documentation

- [User documentation](https://rawcull.netlify.app)
- [Changelog](https://rawcull.netlify.app/blog/)

![](images/rawcull.png)

![](images/nomask.png)

Focus Mask and Focus Point applied.

![](images/focusmask.png)
