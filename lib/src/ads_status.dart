enum AdsStatus { disabled, enabled, testing, hybrid }

/// Who runs the Google UMP consent flow.
enum AdsConsentMode {
  /// The library runs the UMP flow on every launch (consent info update ->
  /// consent form if required) and requests ads only when the SDK's
  /// `canRequestAds` is true. This is the default.
  managed,

  /// The app runs UMP (or another CMP) itself. The library does not touch
  /// consent and does not gate ad requests on it.
  external,
}
