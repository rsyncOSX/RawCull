# macOS Background Assets and RawCull release builds

This document explains how Apple macOS build numbers, RawCull application
versions, code signing, and the AI import-boundary verifier relate to the CLIP
model-download feature. These are separate controls and must not be changed as
though they were one version number.

## Why this is part of RawCull

RawCull downloads optional CLIP model bundles through Managed Background Assets.
That framework coordinates the main application, an embedded downloader
extension, a shared App Group, and a system-managed asset location. A failure in
any of those relationships can make a download unavailable even though the
manifest URL itself is reachable.

Two macOS 27 beta builds were also observed to trap while Background Assets
validated a development-signed application. RawCull therefore contains a narrow
runtime guard in `RawCullAIModelDownloadService.swift`. It disables live model
downloads only when both of these facts are true:

- the current Apple operating-system build is in `affectedMacOS27Builds`; and
- the running RawCull executable is development-signed, as identified by the
  `com.apple.security.get-task-allow` entitlement.

The guard protects Xcode development runs from an operating-system regression. It
does not replace correct signing, entitlements, extension packaging, or release
testing.

## Three identifiers that must not be confused

| Identifier | Example | Owner | When it changes |
|---|---|---|---|
| Apple macOS build | `26A5421a` | Apple | When macOS is updated to another beta, RC, or public build |
| RawCull marketing version | `3.2.0` | RawCull | When the user-facing RawCull release version changes |
| RawCull application build | `350` | RawCull | When a new RawCull release candidate or distributable binary is produced |

Apple's macOS build is available with:

```sh
sw_vers -buildVersion
```

RawCull reads the operating-system version from `ProcessInfo`. Installing a new
macOS beta or RC does not require changing `MARKETING_VERSION` or
`CURRENT_PROJECT_VERSION`.

`MARKETING_VERSION` becomes `CFBundleShortVersionString` in the built application.
`CURRENT_PROJECT_VERSION` becomes `CFBundleVersion`. Signing and notarization use
those values but do not create or increment them.

## What to do for each new macOS beta or RC

1. Install the new macOS build and record `sw_vers -buildVersion`.
2. Build and run RawCull from Xcode.
3. Open **Settings > AI > Download AI Models**, accept the applicable verified
   licence, and test a CLIP download.
4. Test cancellation, removal, and redownload when the download succeeds.
5. If development download succeeds, do not change `affectedMacOS27Builds` or a
   RawCull version merely because macOS changed.
6. If Background Assets still traps during validation on the new Apple build,
   add that exact build to `affectedMacOS27Builds`, add or update the corresponding
   runtime-policy test, and record the observed failure. Do not add a build based
   only on its beta or RC label.
7. Before shipping, repeat the successful-download check with the archived,
   Developer ID-signed application installed and launched normally. An Xcode Run
   and a packaged distribution build exercise different signing states.

The denylist intentionally uses exact Apple build identifiers. A new build is
allowed for development testing by default so that an old beta workaround does
not silently disable downloads forever. If the regression continues in a new
build, that build must be confirmed and added deliberately.

## Signing requirements

The RawCull application and `RawCullModelDownloader` extension must both be signed
and embedded correctly. They use the same App Group:

```text
group.no.blogspot.RawCull.model-assets
```

Both targets must retain the App Sandbox and App Group entitlements. The app must
also retain its `BAAppGroupID`, `BAHasManagedAssetPacks`, `BAManifestURL`, hosting
selection, and download restrictions in `RawCull-Info.plist`.

Xcode signs an ordinary Debug Run with an Apple Development identity when
automatic signing succeeds. Such a build normally contains
`com.apple.security.get-task-allow = true`; it is signed, but it is still a
development-signed build. The release workflow exports a Developer ID-signed app,
verifies both app and extension signatures, notarizes the archive, and staples the
ticket.

The XCTest host is a separate case. Xcode relocates the application bundle for
tests, which Background Assets cannot validate reliably. RawCull therefore uses a
non-routable test manifest under XCTest, and transfer tests inject a deterministic
download service instead of performing live network downloads.

## RawCull version and build policy

Do not change RawCull's versions just because Apple publishes a macOS beta, RC, or
public release.

- Keep `MARKETING_VERSION = 3.2.0` if the AI-enabled release is RawCull 3.2.0.
- Increment `CURRENT_PROJECT_VERSION` before producing a new release candidate or
  distributable binary when the previous build number has already identified an
  earlier artifact.
- Keep the RawCull app and downloader extension on the same marketing version and
  application build.
- If build `350` has never represented a retained, notarized, shared, or published
  candidate, it may remain the final build. If another build `350` already exists
  and the source has changed, use `351` for the next archive.

The repository does not automatically increment `CURRENT_PROJECT_VERSION`.
Update the value in Xcode's target identity/build settings and confirm that both
the app and downloader-extension configurations changed before archiving.

## AI import-boundary verification

`Scripts/VerifyAIImportBoundary.sh` protects the source-code architecture of the
AI feature. It is unrelated to Apple signing and operating-system build numbers,
but it is part of the same release discipline: download behavior depends on the
model-management and composition layers remaining separated from views and
general application state.

Run it through the Makefile:

```sh
make verify-ai-import-boundary
```

The verifier:

- permits restricted PhotoAIKit and concrete backend imports only in exact,
  reviewed production files;
- prevents SwiftUI views from reaching through the focused similarity feature to
  the low-level similarity model;
- prevents the intelligence runtime from exposing that low-level model; and
- prevents removed provider-building initializers and compatibility forwarding
  methods from being reintroduced.

Run it after moving or adding AI code, changing AI imports, changing
`RawCullViewModel` or an AI-facing view, and before an AI-related commit or pull
request. Run it again for every release candidate. It is fast and static, so it is
also reasonable to run it before any commit.

The script does not compile RawCull, validate signatures, download a model, find
unused code, or run tests. A successful result therefore complements rather than
replaces the build, test, signing, notarization, and manual-download gates.

The current `make release-preflight` target does not invoke the boundary verifier.
Until that workflow is changed, run both explicitly:

```sh
make verify-ai-import-boundary
make release-preflight
```

If a necessary import fails the verifier, first confirm that the dependency is in
the narrowest correct intelligence layer. Update the exact allowlist and
`Docs/ai-dependency-boundary.md` together only after that architectural decision;
do not broadly exempt a folder to make the check pass.

## Release evidence checklist

- [ ] Record the Apple macOS build used for testing.
- [ ] Confirm an Xcode development run does not hit a known Background Assets
      regression, or record the exact guarded build.
- [ ] Confirm the app and downloader extension share the expected App Group.
- [ ] Confirm the app and extension have matching RawCull marketing/build values.
- [ ] Run `make verify-ai-import-boundary`.
- [ ] Run the applicable automated model-download and release tests.
- [ ] Archive and verify Developer ID signatures for both binaries.
- [ ] Notarize and staple the packaged application.
- [ ] Install the packaged application and perform a real CLIP download,
      cancellation/removal check, and model validation on the supported macOS
      release.

