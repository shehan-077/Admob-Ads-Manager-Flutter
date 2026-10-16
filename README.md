# AdMob Ads Manager (Flutter)

A manager on top of [`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads) that handles Google UMP consent,
SDK initialization, preloading and showing of full-screen ads, and the banner and native ad widgets. It supports
**Android and iOS only**.

Supported formats: interstitial, app open, rewarded, rewarded interstitial, banners (normal anchored adaptive,
collapsible, inline adaptive, fixed size) and native ads (small and medium templates).

> This library reduces boilerplate; it does not make an app policy compliant. You remain responsible for AdMob policies,
> consent configuration, frequency limits and when ads are shown.

## Requirements

Library minimums (inherited from `google_mobile_ads` 9.1):

| | Minimum |
|---|---|
| Flutter / Dart | Flutter 3.38.1 / Dart 3.10 |
| Android | `minSdk` 24, `compileSdk` 36 |
| iOS | 13.0 (UIScene lifecycle required) |

Example app / development tooling only (not library requirements): the example was built with Flutter 3.44 / Dart 3.12,
Gradle 8.14, Android Gradle Plugin 8.11.1, Kotlin 2.2.20, and its iOS deployment target is 15.0 because Xcode 27 no
longer builds for lower targets.

## Installation

```yaml
dependencies:
  admob_ads_manager:
    git:
      url: https://github.com/shehan-077/Admob-Ads-Manager-Flutter.git
      ref: 2.0.0
```

```dart
import 'package:admob_ads_manager/admob_ads_manager.dart';
```

The entry point also re-exports `AdRequest`, `ConsentDebugSettings` and `DebugGeography` from `google_mobile_ads`.

### Native setup (required)

`AdMobIds.appId` is informational only. The AdMob **app id** must be declared natively or the app crashes at launch.

- **Android** - `android/app/src/main/AndroidManifest.xml`, inside `<application>`:

  ```xml
  <meta-data
      android:name="com.google.android.gms.ads.APPLICATION_ID"
      android:value="ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy"/>
  ```

- **iOS** - `ios/Runner/Info.plist`: add `GADApplicationIdentifier` with your app id and Google's
  [`SKAdNetworkItems`](https://developers.google.com/admob/ios/quick-start#update_your_infoplist). `google_mobile_ads`
  8 and later needs the UIScene lifecycle; let Flutter apply its automatic migration or follow the
  [Flutter UIScene guide](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).

While developing, use Google's sample app ids (`ca-app-pub-3940256099942544~3347511713` on Android,
`ca-app-pub-3940256099942544~1458002511` on iOS).

## Ad units

```dart
final ids = AdMobIds.single(
  appId: 'ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy',
  interstitialId: 'interstitialId',
  bannerId: 'bannerId',
  appOpenId: 'appOpenId',
  rewardedId: 'rewardedId',
  nativeId: 'nativeId',
  rewardedIntId: 'rewardedIntId',
);

final rotating = AdMobIds(
  appId: 'ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy',
  interstitialIds: ['interstitial_1', 'interstitial_2'],
  bannerIds: ['banner_1', 'banner_2'],
  appOpenIds: ['appOpen'],
  rewardedIds: ['rewarded'],
  nativeIds: ['native'],
  rewardedIntIds: ['rewardedInt'],
);
```

Ad units differ per platform in most apps, so pick them per platform:

```dart
final ids = AdMobIds.forPlatform(android: androidIds, ios: iosIds);
```

**Index behaviour.** Every API takes an `index` that selects an entry of the corresponding list; an index beyond the list
wraps around (`index % length`), which gives round-robin over several ad units. A negative index throws an
`ArgumentError` (widgets log it and show nothing).

### Testing versus production

| `AdsStatus` | Behaviour |
|---|---|
| `testing` | Always Google's sample ad units. |
| `enabled` | Always your real ad units, **including in debug builds**. |
| `hybrid` | Sample ad units in debug builds (or after `setForceTestAds(true)`), your real units otherwise. Recommended during development. |
| `disabled` | No ads; see [Ads disabled](#ads-disabled). |

Testing mode never falls back to production ids; on a platform other than Android/iOS it throws `UnsupportedError`.
Banners requested as `BannerAdsType.collapsible` use Google's collapsible sample unit in testing mode.

## Initialization and readiness

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdsManager.instance.init(
    ids: ids,
    status: AdsStatus.hybrid,
    loadingColor: Colors.black,
  );

  runApp(const MyApp());
}
```

`init` parameters: `ids`, `status`, `loadingColor` (overlay shown while a `show*` call loads), `consentMode` (default
`AdsConsentMode.managed`), `consentDebugSettings` and `tagForUnderAgeOfConsent`.

**Start-up never waits for a consent form.** In managed mode `init` returns as soon as the configuration is applied; the
UMP flow continues in the background. Three different facts can be observed:

| Question | API |
|---|---|
| Has consent processing finished? | `await AdsManager.instance.consentReady` (never throws; completes immediately if no flow was started: external mode, ads disabled, or `init` not called) |
| Has the Mobile Ads SDK initialized? | `AdsManager.instance.isSdkInitialized` |
| Can ads be requested right now? | `AdsManager.instance.adsAvailable` (`ValueListenable<bool>`) or `await AdsManager.instance.whenReady()` |

`consentReady` finishes after the consent update, the form, the `canRequestAds()` check and the SDK initialization
**attempt**, but it does **not** promise that ads are available: the user may have declined, or initialization may have
failed.

**`whenReady()` contract.** `Future<bool> whenReady()` completes after `consentReady` and never throws.

| Situation | Result |
|---|---|
| Consent allows requests (`canRequestAds` true) and the SDK initialized | `true` |
| UMP says requests are not allowed (for example consent required but the update failed offline with no stored consent) | `false` |
| UMP update failed but consent from a previous session allows requests | `true` |
| SDK initialization failed, or did not finish within `sdkInitTimeout` (30 s) | `false` |
| `AdsStatus.disabled`, or `init` was not called yet | `false` immediately (it does not wait for a later `init`; call it after `init`) |

Always check the value:

```dart
if (await AdsManager.instance.whenReady()) {
  // ads can be requested now
} else {
  // declined/required consent, offline without stored consent,
  // SDK initialization problem, or ads disabled
}
```

To retry, call `await AdsManager.instance.refreshAvailability()`. It returns the new availability, never throws, and
(managed mode) repeats the consent update and form first when the start-up update failed, for example because the device
was offline. Calls share one flow, so no duplicate form appears. The SDK initialization is retried too. It does not
re-ask consent that was already obtained. `adsAvailable` updates when the result changes, and banner / native widgets
that were waiting then load.

Behaviour while the consent flow is still running:

- `preLoad` returns immediately and is remembered; it runs once ads become available (or is dropped if they never do).
- `show*` reports an error through the handler instead of waiting behind the form.
- Banner and native widgets wait and load automatically when `adsAvailable` becomes true.

## Consent (Google UMP)

### Managed consent (default)

`AdsConsentMode.managed` follows Google's UMP flow on every launch: consent information update, then
`loadAndShowConsentFormIfRequired`, then `canRequestAds()`, and only then `MobileAds.initialize()`. If the update fails,
`canRequestAds()` is still consulted because consent from a previous session may allow requests; an error from
`canRequestAds()` is treated as "not allowed".

`canRequestAds()` gates **every** request: `preLoad`, the automatic re-preload after a full-screen ad, app open,
interstitial, rewarded, rewarded interstitial, banners and native ads. A cached full-screen ad is checked again right
before it is shown. Duplicate initialization, duplicate forms and duplicate requests are prevented while asynchronous
consent paths complete.

**Privacy options.** Google requires an entry point when the privacy-options form is needed:

```dart
ValueListenableBuilder<bool>(
  valueListenable: AdsManager.instance.privacyOptionsRequired,
  builder: (context, required, _) => required
      ? ListTile(
          title: const Text('Privacy settings'),
          onTap: () => AdsManager.instance.showPrivacyOptionsForm(),
        )
      : const SizedBox.shrink(),
)
```

`showPrivacyOptionsForm()` returns `true` when the form completed without error, waits for the start-up flow, and shares
one form between concurrent callers. Afterwards eligibility is re-checked. If requests are no longer allowed, cached ads
are disposed, in-flight requests are discarded (a late ad is disposed, not cached) and banner / native widgets remove
their ads; a full-screen ad already on screen is left to finish. When requests become allowed again, widgets reload and
the SDK is initialized if needed. (This handling is the library's own policy; Google's guide only requires re-checking
`canRequestAds()`.) `await AdsManager.instance.isPrivacyOptionsRequired()` queries the requirement directly.

**Development-only testing.** On iOS the debug geography only applies to a registered test device whose UMP id is printed in Xcode's console; on the simulator it applies automatically.

```dart
await AdsManager.instance.init(
  ids: ids,
  status: AdsStatus.hybrid,
  consentDebugSettings: ConsentDebugSettings(
    debugGeography: DebugGeography.debugGeographyEea,
    testIdentifiers: ['<hashed device id from the log>'],
  ),
);
```

Debug settings are ignored in release builds and only affect registered test devices. Consent is never reset on
startup; in debug builds you can call `AdsManager.instance.debugResetConsent()` explicitly and then `init` again.

### Externally managed consent

```dart
await AdsManager.instance.init(
  ids: ids,
  status: AdsStatus.hybrid,
  consentMode: AdsConsentMode.external,
);
```

Use this if your app already runs UMP or another consent platform. The library then makes no consent calls and does
not gate requests: only call it after your own flow allows ads. `init` awaits the Mobile Ads SDK initialization and
throws if it fails (call `init` again to retry).

### AdMob dashboard setup (done by the consuming app)

The form only appears if it is configured in AdMob under **Privacy & messaging**:

1. Create and publish a **GDPR** message for your app (and US state regulations messages where needed).
2. Enable the **privacy options** entry point in the message; without it `privacyOptionsRequired` never becomes true.
3. On iOS, optionally add an **IDFA explainer** message.
4. Make sure the app id used by the app is the one the messages are attached to, and review the ad technology partner
   list for any mediation partners you use.

### iOS App Tracking Transparency (ATT)

UMP consent and ATT are separate. This library does **not** request ATT. If you want the system prompt, add
`NSUserTrackingUsageDescription` to `Info.plist` and request it yourself (for example with the
`app_tracking_transparency` package) as Google's iOS UMP guide describes, before calling `AdsManager.init`.

## Full-screen ads

```dart
await AdsManager.instance.preLoad(AdsUnit.interstitial, 0);
await AdsManager.instance.preLoad(AdsUnit.rewarded, 0);
await AdsManager.instance.preLoad(AdsUnit.rewardedInt, 0);
await AdsManager.instance.preLoad(AdsUnit.appOpen, 0);
```

`preLoad` never throws: offline, no fill, timeout (`AdsManager.instance.loadTimeout`, 15 s), missing consent or an
initialization error are logged and the future completes normally, so awaiting it at start-up is safe. A fresh cached
ad is not replaced, concurrent calls share one request, ads expire from the cache after 1 hour (4 hours for app open),
and a shown ad is reloaded automatically afterwards. Preloading is never blocked by another ad being shown.

```dart
AdsManager.instance.showInterstitial(
  context,
  0,
  RequestHandlerImpl(
    onSuccess: () => debugPrint('dismissed'),
    onError: (e) => debugPrint('error: $e'),
  ),
);

AdsManager.instance.showAppOpen(context, 0, RequestHandlerImpl(onSuccess: next, onError: (_) => next()));

AdsManager.instance.showRewarded(
  context,
  0,
  RewardedCallbacks(
    onShowed: () => debugPrint('showed'),
    onRewarded: (reward) => grant(reward.amount, reward.type),
    onDismissed: () => debugPrint('dismissed'),
    onError: (e) => debugPrint('could not load/show: $e'),
    onFailedToShow: (e) => debugPrint('failed to show: $e'),
    onLoaded: () {},
    onFailedToLoad: (e) {},
  ),
);

AdsManager.instance.showRewardedInterstitial(context, 0, callbacks);
```

(`RewardedHandlerBuilder` offers the same callbacks as a fluent builder.)

Guarantees and behaviour:

- **Foreground only.** A full-screen ad is only started while the app lifecycle is `resumed` (see
  [Android activity recreation](#android-activity-recreation)); otherwise the error callback fires.
- **One at a time.** Only one full-screen ad (any format) may be loading-for-show or on screen. A second `show*` call
  reports an error through its handler immediately.
- **Exactly one outcome.** Each call ends in one terminal callback: `onSuccess` / `onDismissed`, or an error callback.
  Duplicate native events are ignored. Synchronous and asynchronous `show()` failures are reported once and release the
  lock. If `context` is unmounted, the error callback fires and a loaded ad stays cached.
- **Timeouts.** After a timeout the call reports an error. A late ad is cached (or disposed if it became obsolete, for
  example after consent was withdrawn); it is never shown by the timed-out call, and it can never release a lock owned by
  a newer call.
- **Rewards.** `onRewarded` fires only from the SDK's user-earned-reward callback and at most once per ad. Dismissal
  never grants a reward. The SDK normally reports the reward before dismissal; if it reports it after dismissal, the
  reward is still delivered once, after `onDismissed`, so grant rewards in `onRewarded` only and do not assume an order.
  Error values are the SDK's `LoadAdError` / `AdError` objects for rewarded callbacks and strings for
  `RequestHandler.onError`.
- **Loading overlay.** When nothing is cached, a spinner overlay (`loadingColor`) is shown while loading.

### Ads disabled

With `AdsStatus.disabled` (for example a premium user) nothing is requested, consent is not run and the SDK is not
initialized. `showInterstitial` / `showAppOpen` call `onSuccess` immediately; rewarded variants call `onDismissed` and
**do not grant a reward**: handle ad-free users in your own code. Banner and native widgets render nothing.

## Banner ads

```dart
const BannerAdContainer(
  index: 0,
  type: BannerAdsType.normal,
);

const BannerAdContainer(
  index: 0,
  type: BannerAdsType.collapsible,
);

const BannerAdContainer(
  index: 0,
  type: BannerAdsType.inlineAdaptive,
);

const BannerAdContainer(
  index: 0,
  type: BannerAdsType.fixed,
  size: BannerAdsSize.banner,
);
```

`BannerAdContainer(index: 0)` is the same as `type: BannerAdsType.normal`. Optional parameters: `size`
(`BannerAdsSize`, fixed only, default `banner`), `collapsiblePlacement` (`BannerCollapsiblePlacement.bottom` default or
`top`), `maxHeight` (dp, inline adaptive only) and `request` (an `AdRequest`; the collapsible extra is merged into your
extras, other fields are preserved).

All banner types: the ad is requested only when `adsAvailable` is true; it reloads only when the index, type, size,
placement, max height, available width or orientation change (not on rebuilds, keyboard changes or scrolling); a replaced
or failed ad is disposed exactly once; stale callbacks are ignored; and each ad instance is attached to one widget only.

| Type | Details |
|---|---|
| `normal` | Anchored adaptive banner. The width comes from the widget's layout constraints (parent padding is already excluded; when the widget spans the whole screen, remaining horizontal safe-area insets are removed). It uses `AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation` because the previous API is deprecated, so banners can be **taller** than in earlier versions; the container takes the height the SDK returns. |
| `collapsible` | Same collapsed size plus the `collapsible` extra (`bottom` or `top`). **Place the widget at the screen edge named by `collapsiblePlacement`** (for `bottom`, for example `Scaffold.bottomNavigationBar`; for `top`, at the top of the screen); the expanded overlay is anchored to that edge. If Google returns a normal banner instead of a collapsible one, that counts as a successful load. Refreshes configured in AdMob are not collapsible, and the library never reloads on a timer. Collapsible ads are served for Google demand only. |
| `inlineAdaptive` | For scrolling content such as a `ListView`; do not use it as a fixed bar. The SDK chooses the height (at most `maxHeight`, or the screen height); after the ad loads the library reads the real height with `BannerAd.getPlatformAdSize()` and sizes the container to it. Results that arrive after disposal, replacement or rotation are discarded. |
| `fixed` | `banner` 320x50, `largeBanner` 320x100, `mediumRectangle` 300x250 (phones and tablets); `fullBanner` 468x60 and `leaderboard` 728x90 (**tablets**). Ads are never scaled, cropped or stretched: if the widget's constraints are smaller than the ad, nothing is loaded and a debug message names the size and the shortfall. Give the widget at least the ad size, including padding. |

Failed loads (no fill, offline) are **not** retried automatically; see [Retrying failed loads](#retrying-failed-loads).

## Native ads

```dart
const NativeAdsContainer(
  index: 0,
  size: NativeAdsSize.small,
);
```

`NativeAdsSize.medium` selects the medium template. The default container height is 120 dp for small and, for medium,
0.92 x the available width clamped to 320-400 dp (a fixed 320 dp clipped the call-to-action on a 392 dp wide phone during
device testing; the width-based default showed it fully on that phone). Optional `height` is clamped to Google's
documented template ranges (small 90-200, medium 320-400) and `maxWidth` limits the width (Google recommends at most
400 dp; the default is the available width, and the minimum recommended width is 320).

**iOS: `small` uses the medium template on narrow screens.** Google's iOS small template limits its media area to a
quarter of its own width (the constraint is in the SDK's `GADTSmallTemplateView.xib`: media width <= 0.25 x width, square).
A MediaView that shows video must be at least 120x120 points (the AdMob native ad validator reports "MediaView is too
small for video" otherwise), which needs a width of at least 480 pt, so no container height can make the small template
compliant on an iPhone (about 99 pt of media at 393 pt width, seen on an iPhone 15 Pro). Therefore, on iOS, when the
available width is below 480 pt, `NativeAdsSize.small` requests and renders the **medium** template (full-width media,
height 320-400 dp, the `height` you pass is ignored in that case). At 480 pt and wider (iPad, landscape) and on all of
Android, `small` stays the compact template; Android's small template has no media view. `iosSmallMediaFallback: false`
keeps the compact template on iPhone and accepts the validator warning for video creatives:

```dart
const NativeAdsContainer(index: 0, size: NativeAdsSize.small);                       // medium template on narrow iOS
const NativeAdsContainer(index: 0, size: NativeAdsSize.small, iosSmallMediaFallback: false); // always compact
```

The template follows the available width, so rotating or resizing across 480 pt requests a new ad. Layout was checked on
one Android phone (392 dp wide) and one iPhone 15 Pro; check clipping on your own target screen sizes. In a lazy list (`ListView.builder`) an ad that scrolls
out of the cache extent is disposed and requested again when it returns.

The ad is requested when `adsAvailable` becomes true, and again when `index` or `size` change.

## Retrying failed loads

```dart
AdsManager.instance.retryFailedAds();                                  // all failed banners and native ads
AdsManager.instance.retryFailedAds(unit: AdsUnit.banner);              // banners only
AdsManager.instance.retryFailedAds(unit: AdsUnit.native, index: 0);    // one slot
```

Works with the const widgets, no controller or key needed. Only widgets whose last load failed and that currently hold
no ad react. Widgets that already show an ad, are still loading, or cannot request ads (ads disabled, SDK not
initialized, consent missing) ignore the call. There are no automatic retries and no refresh timers; call it from your
own UI (for example a "Retry" button) or after connectivity returns.

## Android activity recreation

With the default `FlutterActivity`, destroying the Activity (for example the **Don't keep activities** developer option,
or the system reclaiming it) destroys the Flutter engine, so the Dart isolate restarts: `main()` runs again,
`AdsManager` starts fresh, consent is re-checked, and caches, locks, callbacks and navigation state are gone. The process
itself survives, which is different from process death. Consequences seen on a device:

- Banner and native ads are requested again after recreation and the full-screen single-flight lock cannot stay stuck.
- A full-screen ad that was already on screen is restored by the Google Mobile Ads SDK, but the Dart callbacks of the
  call that showed it are lost. `onSuccess` / `onDismissed` never fire for it, and a reward earned while the Activity was
  destroyed is **not delivered** to `onRewarded`. Do not rely on callbacks alone for anything that must survive: verify
  rewards on your server (AdMob server-side verification) or keep a pending-action record that you resolve when the app
  starts again.
- Keep non-ad continuations (navigation, unsubscribe, purchases) independent of ad callbacks.
- This is a known limitation of Activity destruction, not something the library can recover: the rewarded ad's Dart
  continuation no longer exists when the reward is earned.
- After recreation the SDK may restore the ad that was on screen. The library will **not** start another full-screen ad
  on top of it: a request is only started while the app lifecycle state is `resumed`. State `inactive` (an ad or system
  dialog is covering the app) waits up to `AdsManager.instance.foregroundWait` (2 s) for `resumed` and is then refused
  with an error through the handler; `paused`, `hidden` and `detached` are refused at once. Automatic ads (for example an
  app-open ad on start-up) therefore cannot stack on a restored ad. Your handler's error branch must continue the app's
  normal flow.

## Trying the example on a device

```bash
cd example
flutter run -d <android-device-id> \
  --dart-define=UMP_TEST_DEVICE=<hashed id from the UserMessagingPlatform log line> \
  --dart-define=UMP_EEA=true
# add --dart-define=UMP_RESET=true once to clear stored consent (debug builds only)
```

The example uses Google's sample app ids and `AdsStatus.hybrid`, so only test ads are requested in debug builds. Without
the `UMP_*` defines no consent debug settings are used.

## What your app is responsible for

- Frequency caps, cooldowns and placement rules for full-screen ads.
- When to show app open ads. The library only shows one when you call `showAppOpen`; wire it to your own cold-start
  and resume logic (for example `AppLifecycleListener`), and respect the 4-hour expiry.
- Not rewarding users except from `onRewarded`, and handling premium / ad-free users.
- The AdMob dashboard privacy messages, the native app id setup and, on iOS, ATT.
- Verifying behaviour on real devices with test ads before releasing.

## Adopting it in an existing app

- Waiting for the start-up consent flow before an automatic ad (for example an app-open ad on the splash screen): the
  `show*` calls refuse while the consent form is open. Wait with a bound and continue without an ad if it is not ready:

  ```dart
  final ready = await AdsManager.instance.whenReady().timeout(
    const Duration(seconds: 3),
    onTimeout: () => false,
  );
  if (!ready) return; // continue the normal flow without an ad
  ```
- Keep essential actions (navigation, unsubscribe, purchases) in the error branches of every handler.
- Keep your own frequency caps and premium checks before calling the library.
- Use `consentMode: AdsConsentMode.external` if the app already owns UMP.
- If the app depends on `google_mobile_ads` directly, raise its constraint to `^9.1.0`.

## Migration

From 1.x:

- **Consent is now managed by default.** Apps that already show a UMP form must pass
  `consentMode: AdsConsentMode.external`, otherwise two flows run; remove manual `MobileAds.instance.initialize()` calls
  when using managed mode. Apps that did no consent handling now get the UMP flow; configure the privacy message in AdMob.
- **`await init` timing.** In managed mode `init` returns before consent finishes. Code that assumed the SDK was
  initialized afterwards should use `whenReady()` or `adsAvailable`.
- **`preLoad` no longer throws** and is deferred while the consent form is open; `show*` calls fail fast during that time
  and when another full-screen ad is loading or showing.
- **Error types.** Rewarded interstitial callbacks now receive the SDK error objects (as rewarded already did) instead of
  strings; `RequestHandler.onError` still receives strings. `RewardedCallbacks.onLoaded` / `onFailedToLoad` are now
  actually invoked.
- **Negative indexes** throw `ArgumentError` instead of wrapping; indexes beyond the list still wrap.
- **Banners.** `BannerAdContainer(index: 0)` still works. Normal banners use the large anchored adaptive size (taller),
  and reload on width/orientation changes. Native medium default height is width-based (320-400 dp) instead of a fixed 300.
- **Requirements.** Flutter 3.38.1+ / Dart 3.10+, `google_mobile_ads` 9.1, UIScene lifecycle on iOS. The unused
  `plugin_platform_interface` dependency was removed.

See [CHANGELOG.md](CHANGELOG.md) for details and [docs/AD_LIBRARY_AUDIT.md](docs/AD_LIBRARY_AUDIT.md) for the audit
notes, verification results and the device checks that are still open.
