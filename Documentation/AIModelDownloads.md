# AI model download service

RawCull uses Managed Background Assets for optional AI model bundles. The app
talks only to `AssetPackManager`; the downloader extension selects whether the
packs are self-hosted or Apple-hosted.

The current build is deliberately configured for self-hosting with the
non-routable placeholder:

`https://example.invalid/rawcull/models/manifest.json`

This keeps the full user interface, progress, cancellation, removal, local
licence acceptance, and model validation path in place without making a live
network request.

The app and extension share only the Managed Background Assets container
`group.no.blogspot.RawCull.model-assets`. This identifier is also recorded as
`BAAppGroupID` in the app Info.plist.

## Hosting decision

Self-hosting is the current default because RawCull's documented distribution
is a Developer ID DMG. Apple-hosted asset packs are appropriate only for an App
Store or TestFlight build. The extension already contains an Apple-hosted
`StoreDownloaderExtension` variant behind the
`RAWCULL_APPLE_HOSTED_MODEL_ASSETS` compilation condition, so the application
service and UI do not change when hosting changes.

For an Apple-hosted configuration:

1. Upload approved packs in App Store Connect.
2. Add `RAWCULL_APPLE_HOSTED_MODEL_ASSETS` to the downloader extension.
3. Set `BAUsesAppleHosting` to `YES`.
4. Remove `BAManifestURL` from the app target.
5. Archive and test the App Store configuration.

Do not enable both hosting configurations in one product.

## Licence audit

The audit source was `~/Downloads/ailicences.md` and its
`THIRD-PARTY-NOTICES` directory.

- OpenCLIP/DataComp: a complete MIT notice is bundled, but release remains
  blocked until the exact source-checkpoint revision and source-file checksums
  are cryptographically recorded with the converted archive.
- OpenAI CLIP: the bundled MIT notice covers the source/tokenizer. Release
  remains blocked until the exact weights licence, immutable revision, and
  source checksums are verified.
- Meta SAM 3: the Downloads catalogue describes a gated, non-MIT licence, but
  no complete licence document was present. Release remains blocked until that
  text is packaged and ungated redistribution is confirmed compatible with
  Meta's licence and official access conditions.

The production catalogue therefore cannot start any real model download. A
descriptor becomes downloadable only after its `releaseReadiness` changes to
`ready`, its archive metadata is complete, and any required verified licence
has been accepted.

## Security and privacy boundary

Managed Background Assets owns transport and installation. RawCull never
constructs arbitrary destination paths from a server response. It asks the
framework for a known asset-pack ID and a catalogue-owned relative model path,
then passes that directory through the existing model-bundle validation before
using it.

The licence acceptance store records model ID/version, licence version and
text checksum, date, and RawCull version. A changed licence checksum invalidates
old acceptance automatically.

Model downloads send only the connection information necessary to serve the
asset. Photographs, embeddings, masks, prompts, and inference results are not
part of this flow.
