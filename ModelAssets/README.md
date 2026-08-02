# RawCull model asset packs

`manifest.template.json` is the developer-side Managed Background Assets
manifest skeleton for the three optional model bundles. It contains no model
files and is not served by the application.

`Notices` is the checked-in source for each pack's licence, attribution, and
provenance catalog. Copy the matching catalog into the release staging tree at
`Notices/<bundle-name>` before packaging. A catalog documents known evidence;
its presence does not override a release blocker in
`RawCullAIModelDownloadCatalog.production`.

Before publishing a pack:

1. Resolve the corresponding release blocker in
   `RawCullAIModelDownloadCatalog.production`.
2. Put the converted bundle, complete applicable licence text, provenance,
   conversion metadata, and checksums under the selector's source directory.
3. Generate the deployable manifest and archives with the Managed Background
   Assets tools in the release version of Xcode.
4. Upload the archives first and the generated manifest last.
5. Replace RawCull's `.invalid` `BAManifestURL` only after verifying the
   production files over HTTPS.

For Apple hosting, upload the same packs in App Store Connect, set
`BAUsesAppleHosting` to `YES`, remove `BAManifestURL`, and compile the extension
with `RAWCULL_APPLE_HOSTED_MODEL_ASSETS`.
