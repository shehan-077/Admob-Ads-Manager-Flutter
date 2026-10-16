## 2.0.0

### Compatibility changes (read before upgrading)
* **Consent default:** UMP consent is handled by the library by default (`AdsConsentMode.managed`). Apps that already run UMP must pass `consentMode: AdsConsentMode.external`.
* **`init` timing:** in managed mode `init` returns before the consent flow finishes. Use `whenReady()`, `adsAvailable` or `consentReady` (consent processing only) to observe progress.
* **`preLoad`** never throws and is deferred while the consent form is open; `show*` fails fast during that time and when another full-screen ad is loading or showing.
* **Error types:** rewarded interstitial `onError` / `onFailedToShow` now receive SDK error objects (like rewarded); `RequestHandler.onError` still receives strings. `RewardedCallbacks.onLoaded` / `onFailedToLoad` are now invoked.
* **Negative ad indexes** throw `ArgumentError`; indexes beyond the list still wrap.
* **Banners:** normal banners use `getLargeAnchoredAdaptiveBannerAdSizeWithOrientation` (the previous API is deprecated) and can be taller; they reload when width or orientation change. Native medium default height is width-based, 320-400 dp (was a fixed 300).
* **Requirements:** `google_mobile_ads` ^9.1.0, Flutter >= 3.38.1 (was declared >= 3.3.0), Dart >= 3.10, iOS UIScene lifecycle. The unused `plugin_platform_interface` dependency was removed.

* **Foreground rule:** full-screen ads are only started while the app lifecycle is `resumed`; `inactive` waits up to `AdsManager.foregroundWait` (2 s), `paused`/`hidden`/`detached` are refused. This stops an automatic ad from stacking on an ad the SDK restored after Android Activity recreation.

* **iOS native `small` template:** on iOS, `NativeAdsSize.small` uses the medium template when the available width is below 480 pt, because Google's iOS small template caps its media area at 25% of its width and can never reach the 120x120 point minimum for a video MediaView (the AdMob native ad validator reported "MediaView is too small for video" on an iPhone). Use `iosSmallMediaFallback: false` to keep the compact template. Android is unchanged.

### Added
* `BannerAdContainer(type:, size:, collapsiblePlacement:, maxHeight:, request:)` with `BannerAdsType` (`normal`, `collapsible`, `inlineAdaptive`, `fixed`), `BannerAdsSize`, `BannerCollapsiblePlacement`. `BannerAdContainer(index: 0)` still works.
* `NativeAdsContainer(height:, maxWidth:, iosSmallMediaFallback:)`; heights are clamped to Google's documented template ranges. The medium default height is 0.92 x the available width within 320-400 dp (a fixed 320 clipped the call-to-action on a 392 dp phone).
* Managed / external UMP consent: `AdsConsentMode`, `consentDebugSettings`, `tagForUnderAgeOfConsent`, `privacyOptionsRequired`, `showPrivacyOptionsForm()`, `isPrivacyOptionsRequired()`, `debugResetConsent()` (debug builds only).
* Readiness: `consentReady`, `isSdkInitialized`, `adsAvailable`, `whenReady()`, `refreshAvailability()`, `sdkInitTimeout`.
* `refreshAvailability()` repeats a failed start-up consent update (for example after an offline launch) before re-checking eligibility.
* `AdsManager.retryFailedAds({unit, index})` to retry failed banner / native loads on demand.
* `AdsManager.getBannerAdUnitId`, `AdMobIds.forPlatform`, `AdsManager.loadTimeout`.
* Regression tests (134) and example pages for every banner type, privacy settings and retry.

### Fixed
* `preLoad` rethrowing load errors (offline start-up) and unhandled errors from the automatic re-preload.
* Double disposal in `AdPreloadCache`, and a showing ad being disposed by a concurrent preload; cached ads now expire (1 h, 4 h for app open).
* Overlapping full-screen ads; callbacks firing more than once; lost callbacks when the context was unmounted; a late callback after a timeout can no longer show an obsolete ad or release a newer operation's lock, and obsolete late ads are disposed.
* Rewards fire only from the SDK reward callback, once per ad.
* Loading overlay throwing without an `Overlay` or being hidden by a concurrent request.
* Concurrent consent / SDK initialization / privacy-form calls now share one flow; eligibility refreshes are ordered so the latest wins; SDK initialization has a timeout and can be retried.
* Banner widgets built with `Align` expanded to fill bounded parents (a collapsible banner in `bottomNavigationBar` was drawn mid-screen); they now shrink-wrap and keep the ad's own size.
* Banner / native widgets: crashes before `init`, stale callbacks after index / type / size changes, leaks when disposed while loading, retry storms on rebuild.
* Testing mode no longer falls through to production ids on unsupported platforms.
* README errors (parameter names, `onRewarded` signature, pubspec snippet); example test that could not pass.

### Repository
* `pubspec.yaml` description, `homepage` and `repository` (taken from the Git remote); the generated Android build report is no longer tracked and `build/` is ignored under `example/android`.
