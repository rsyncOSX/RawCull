#if RAWCULL_APPLE_HOSTED_MODEL_ASSETS
    import ExtensionFoundation
    import StoreKit

    /// Apple-hosted Managed Background Assets entry point.
    ///
    /// Enable `RAWCULL_APPLE_HOSTED_MODEL_ASSETS` only for an App Store or
    /// TestFlight configuration whose asset packs have been uploaded to Apple.
    @main
    struct RawCullModelDownloader: StoreDownloaderExtension {}
#else
    import BackgroundAssets
    import ExtensionFoundation

    /// Self-hosted Managed Background Assets entry point.
    ///
    /// The framework provides the download scheduling and installation behavior.
    /// RawCull intentionally accepts the default policy from its asset-pack
    /// manifest, so there is no custom networking or background-session code here.
    @main
    struct RawCullModelDownloader: ManagedDownloaderExtension {}
#endif
