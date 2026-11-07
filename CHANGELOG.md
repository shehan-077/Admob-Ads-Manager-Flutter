## 2.0.1

Reliability patch: fewer lost ad opportunities, no change to ad frequency. The library still has no cooldown, minimum
interval or frequency cap; display frequency stays the app's decision. Consent is never bypassed: nothing is requested
or shown while `canRequestAds` is false.

### Consent start-up
* `show*` calls made while the managed consent flow is still running now wait up to `AdsManager.consentWait` (3 s)
  instead of failing at once, so `await init()` followed by an immediate `showAppOpen()` no longer loses the
  opportunity when consent finishes quickly. If it does not finish in time, or consent is denied, the handler gets
  exactly one error. `init()` still returns before the flow completes.
* The consent information update is bounded by `consentUpdateTimeout` (30 s); a hung update counts as failed and can
  be recovered instead of keeping the manager in "consent in progress" forever.

### Offline initialization recovery
* After a failed consent update (for example an offline first launch) a later `show*`, a `preLoad`, a banner / native
  widget that wants to load, or the app returning to the foreground retries the update, at most once per
  `AdsManager.recoveryInterval` (30 s). `refreshAvailability()` still works at any time.
* `preLoad` intent is kept (bounded, one entry per slot) while ads are unavailable and runs after recovery or after the
  user's consent choices change; it is no longer discarded.
* A `canRequestAds()` platform error no longer clears cached ads or hides visible banners / native ads; it is treated as
  "unknown" and re-checked later.

### Full-screen coordination
* Loading and presenting are separate. The single-full-screen-ad rule is unchanged, but the lock is now taken only when
  an ad is about to be presented, so a ready ad of another format is no longer refused because an unrelated ad is
  still loading. A request whose load finishes while another ad is showing, or after another ad was presented, is
  refused with an error (nothing is queued) and its loaded ad stays cached.
* Two requests for the same slot cannot present one ad twice; overlapping loads keep the loading spinner until the
  last one ends.
* An exception while presenting an ad now disposes the ad, releases the lock and reports one error (previously the lock
  could stay held).
* An ad that never reports that it started showing, nor a dismissal or failure, is failed after
  `AdsManager.showStartTimeout` (10 s) and the lock released. An ad that did start showing is never released by a timer.

### Lifecycle
* A request made while the lifecycle state is `hidden` or `paused` but moving towards `resumed` (the moments of a
  normal resume) now waits up to `foregroundWait` (2 s, unchanged) like `inactive` does; moving away again, a timeout,
  or `detached` still refuses. An ad is still only started while `resumed`. The error names the lifecycle state.

### Banner / native
* A banner or native widget built while ads are unavailable asks the manager to recover and loads as soon as ads
  become available.
* Failed banner / native loads are retried once when the app returns to the foreground (at most once per
  `recoveryInterval`; switch off with `AdsManager.retryFailedAdsOnResume = false`). `retryFailedAds()` is unchanged.
* The large anchored adaptive banner size introduced in 2.0.0 is kept.

### Diagnostics
* Debug builds log the life of each full-screen request (`op<N> <format>#<index>`): requested, cache hit / miss,
  accepted or rejected with the reason, shown, impression, dismissed, plus load start / result and consent recovery.
  Nothing is logged in release builds and no identifiers are logged.

### Tests
* 34 new regression tests (`test/impression_reliability_test.dart`) with fake SDKs: consent timing, denial and
  timeouts, offline recovery, concurrent requests, load / present coordination, stale callbacks, lifecycle sequences,
  resume retry. The existing tests were adapted where the intended behaviour changed (waiting instead of failing).

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
