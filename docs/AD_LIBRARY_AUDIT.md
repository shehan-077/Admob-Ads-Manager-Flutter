# AdMob Ads Manager - Audit

Date: 2026-10-16 (third pass plus Android device testing). Scope: `lib/`, `test/`, `example/` (Dart, Android and iOS configuration), README, dependencies.
Environment: Flutter 3.44.0 / Dart 3.12.0, Xcode 27.1, Android SDK present, macOS host. No physical device or emulator was used.

## 1. Architecture

| File | Role |
|---|---|
| `lib/src/ads_manager.dart` | `AdsManager` singleton: `init`, managed or external UMP consent, readiness (`consentReady`, `isSdkInitialized`, `adsAvailable`, `whenReady`, `refreshAvailability`), ad-unit selection, `preLoad`, the four `show*` methods (one shared pipeline with an operation-token lock), privacy options, `retryFailedAds`. |
| `lib/src/ad_preload_cache.dart` | Per `(unit, index)` cache with expiry and explicit ownership (`take`). |
| `lib/src/ads_sdk.dart` (internal) | Seam over `google_mobile_ads` / UMP static APIs, banner and native factories and `AdWidget`, so logic is testable with mocks. |
| `lib/src/banner_ads_widget.dart`, `native_ads_widget.dart` | `BannerAdContainer` (normal, collapsible, inline adaptive, fixed) and `NativeAdsContainer`: each owns at most one ad, listens to `adsAvailable` and to retry requests. |
| `lib/src/banner_types.dart`, `banner_config.dart` | Public banner enums; internal request building, width resolution, fit check, native height clamp, dispose-once helper. |
| `lib/src/loading_overlay.dart`, `request_handler.dart`, `admob_ids.dart`, `ads_status.dart`, `ads_unit.dart` | Overlay, callback types, id configuration, enums. |

Startup: `init()` -> (managed) background UMP flow -> `canRequestAds()` -> `MobileAds.initialize()` -> `adsAvailable = true`.

Readiness semantics (verified in code and covered by tests):
* `consentReady`: consent processing and the following eligibility/SDK-init attempt have settled. Never throws; completes immediately if no flow was started. It does **not** mean ads are available.
* `isSdkInitialized`: `MobileAds.initialize()` completed successfully.
* `adsAvailable` / `whenReady()`: ads can be requested now (configured, enabled, SDK initialized, consent allows). `whenReady()` never throws and cannot hang on disabled ads or denied consent.
* SDK initialization failure or timeout leaves ads unavailable; `refreshAvailability()` (or the next request, for initialization only) retries.

## 2. Findings and status

Status: **Fixed** (change plus mocked regression test), **Fixed (untested)**, **Open**.

### Critical
| # | Finding | Status |
|---|---|---|
| C1 | `preLoad` rethrew load errors; awaited at start-up (example, README) -> blank screen when offline | Fixed |
| C2 | Re-preload after dismissal was fire-and-forget with a throwing future (unhandled async error) | Fixed |
| C3 | No UMP consent flow; ads requested unconditionally | Fixed - managed consent is the default, `AdsConsentMode.external` opts out |

### High
| # | Finding | Status |
|---|---|---|
| H1 | `AdPreloadCache.remove` returned nothing and callers also disposed -> double dispose | Fixed |
| H2 | `set`/`preLoad` could dispose an ad that was currently showing | Fixed (ownership via `take`) |
| H3 | Overlapping full-screen ads across formats | Fixed (single-flight) |
| H4 | Duplicate error callbacks on load failure | Fixed |
| H5 | Unmounted context -> ad disposed and no callback (lost continuation) | Fixed |
| H6 | Overlay shown outside `try`, throws without `Overlay`, hidden by concurrent request | Fixed |
| H7 | No load timeout | Fixed (15 s; late ads cached or disposed) |
| H8 | No expiry of cached ads | Fixed (1 h / 4 h) |
| H9 | Widgets threw before `init` | Fixed |
| H10 | Banner/native stale-callback and replacement races | Fixed |
| H11 | Consent flow blocked `init`, raced `preLoad`, widgets created early never loaded, withdrawal left ads | Fixed |
| H12 | Boolean fullscreen lock could be released by a stale operation's late callback | Fixed (operation token) |
| H13 | Late ad after timeout could be cached after consent withdrawal / disable | Fixed (epoch check; disposed) |

### Medium
| # | Finding | Status |
|---|---|---|
| M1 | `RewardedCallbacks.onLoaded` / `onFailedToLoad` never invoked | Fixed |
| M2 | Rewards/terminal callbacks could fire more than once | Fixed; ordering contract tested (see below) |
| M3 | `ad.show()` synchronous/asynchronous failures left the lock stuck | Fixed (tests for both) |
| M4 | Testing mode fell through to production ids on unsupported platforms | Fixed |
| M5 | Concurrent `init` / privacy forms / eligibility refreshes could duplicate work or apply out of order | Fixed (single-flight; latest refresh wins) |
| M6 | Banner reloaded on every `MediaQuery` change, never on rotation | Fixed |
| M7 | Inconsistent index and error types | Fixed (negative index rejected; objects for rewarded callbacks) |
| M8 | README errors, broken example test | Fixed |
| M9 | A hanging `MobileAds.initialize()` would hang readiness | Fixed (`sdkInitTimeout`, 30 s; late init is not lost) |
| M10 | Failed banner/native loads could only be retried by changing configuration | Fixed - `AdsManager.retryFailedAds` |
| M11 | Native medium container (fixed 300 dp, then 320 dp) was too short; the 320 dp version clipped the call-to-action on the test phone | Fixed (default 0.92 x width within 320-400; optional `height`/`maxWidth`, clamped); re-checked on the phone (see section 8) |
| M12 | Device test: `Align` without size factors made banners fill bounded parents, so a collapsible banner in `bottomNavigationBar` drew mid-screen and its expanded overlay was anchored there | Fixed (`widthFactor`/`heightFactor` 1, native `heightFactor` 1); regression tests; re-tested on the phone |
| M14 | Device test: after Activity recreation an automatic app-open ad (2 s timer in the example) was started on top of the ad the SDK had restored (two creatives stacked) | Fixed - full-screen ads start only while the lifecycle is `resumed`; `inactive` waits `foregroundWait` (2 s) then refuses; `paused`/`hidden`/`detached` refuse at once; mocked tests; re-tested on the phone |
| M13 | Device test: after an offline launch with no stored consent, ads stayed unavailable until restart because `refreshAvailability()` did not repeat the failed consent update | Fixed; tests; recovery re-tested on the phone |

### Low / informational
| # | Finding | Status |
|---|---|---|
| L1 | `AdMobIds.appId` is informational; native app id must be configured natively | Documented |
| L2 | `AdsStatus.enabled` uses production ids in debug builds | By design; documented |
| L3 | Ads disabled -> rewarded `onDismissed` fires, no reward | Kept; documented |
| L4 | Deprecated `getAnchoredAdaptiveBannerAdSize` | Fixed - large anchored API; banners can be taller |
| L5 | No frequency caps, cooldowns, app-open lifecycle trigger | Not provided; documented as app responsibility |
| L6 | Unused `plugin_platform_interface` | Removed |
| L7 | pubspec metadata minimal | Fixed using the Git remote URL only (no author fields added) |
| L8 | Generated `example/android/build/reports/problems/problems-report.html` tracked | Removed from the index (`git rm --cached`, file left on disk) and ignored |
| L9 | Example iOS target 13 rejected by Xcode 27 | Fixed in the example (15.0) |
| L10 | Android example prints Flutter's "migrate to Built-in Kotlin" warning | Open (toolchain migration, out of scope) |

### Reward callback ordering (resolved contradiction)
Verified in `AdsManager.showRewarded` / `showRewardedInterstitial` and covered by `test/readiness_rewards_test.dart`:
* `onRewarded` fires only from the SDK's user-earned-reward callback, at most once per ad.
* Reward before dismissal: `onRewarded`, then `onDismissed`.
* Reward reported after dismissal: still delivered once, after `onDismissed` (the SDK said the user earned it); the library does not drop it.
* Dismissal alone, repeated dismissal, or duplicate rewards never produce a reward or a second callback.
Whether real SDKs ever report a reward after dismissal is device-only knowledge and unverified.

## 3. Dependencies

| Package | Previous | Updated | Notes |
|---|---|---|---|
| `google_mobile_ads` | ^8.0.0 (8.0.0) | ^9.1.0 (9.1.0) | GMA Android 25.4.0, iOS 13.7.0, UMP 4.0.0 / 3.1.0; preloading APIs added (unused). No API used here was removed. Needs Flutter >= 3.38.1, Dart >= 3.10 (same as 8.x). |
| `plugin_platform_interface` | ^2.1.8 | removed | Unused. |
| `cupertino_icons` (example) | ^1.0.8 | ^2.0.0 | Example only. |
| `flutter_lints` | ^6.0.0 | unchanged | Latest. |
| Transitives (example lockfile) | webview_flutter 4.13.1, _android 4.12.0, _wkwebview 3.25.1, vm_service 15.2.0, platform 3.1.6, process 5.0.5, webdriver 3.1.0 | 4.14.1, 4.14.1, 3.26.2, 15.4.0, 3.2.0, 5.0.6, 3.2.0 | Via `pub upgrade`. Root `pubspec.lock` stays ignored (library policy). |

Still outdated, not upgradable: `meta`, `vector_math`, `clock`, `matcher`, `stack_trace`, `test_api`, `material_color_utilities` (pinned by the Flutter SDK); `webview_flutter_wkwebview` 3.27.0 requires Dart ^3.13.0 (installed 3.12.0). No dependency overrides. Native tooling unchanged (Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20).

## 4. Compatibility changes
See README "Migration" and CHANGELOG: managed consent default, `init` timing, `preLoad`/`show*` behaviour during consent, callback error types, negative-index rejection, taller normal banners, native medium default 320, Flutter 3.38.1 / Dart 3.10 / iOS UIScene requirements.

## 5. Verification (final run)

Mocked unit/widget coverage (not real SDKs):

| Command | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test example/lib example/test` | exit 0 |
| `flutter analyze` (root) / `cd example && flutter analyze` | No issues found / No issues found |
| `flutter test` (root) | 128 passed (`ads_manager_test.dart`, `banner_test.dart`, `readiness_rewards_test.dart`) |
| `cd example && flutter test` | 1 passed (opens each banner demo page) |
| `git diff --check` | exit 0 |
| README examples | Compiled in a temporary file with `flutter analyze` (removed afterwards); no errors |

Build verification (compiles; says nothing about runtime ad behaviour):

| Command | Result |
|---|---|
| `flutter build apk --debug` | Success |
| `flutter build ios --debug --no-codesign` | Success |
| `flutter build apk --release` | Success (48.5 MB; uses the example project's configured signing, no credentials touched) |
| `flutter build ios --release --no-codesign` | Success (20.4 MB) |

Coverage added in this pass: reward ordering/duplicates, asynchronous and synchronous `show()` failures, timeout then late callbacks (including lock ownership), consent changes while loads are pending, SDK init failure/timeout/recovery, readiness futures, banner/native index/type/size changes while loading, orientation and width changes, inline platform-size resolution after disposal/replacement/rotation, retry semantics, native sizing. These tests passed without needing implementation changes beyond those made alongside them (readiness APIs, init timeout, refresh ordering, retry, native sizing).

## 6. Device-only checks still pending
Section 8 lists what was tested on one Android phone; the items below that are not marked tested there are still pending.
1. **UMP:** form display, decline/limit then `canRequestAds`, privacy-options entry visibility, `debugGeography` with a registered test device, withdrawal while ads are cached or banners are visible, behaviour when offline at launch.
2. **Banners:** collapsible expand/collapse at both placements (and a mismatched placement), inline heights in a scroll view, large anchored banner heights on small phones, rotation, foldable/tablet resizing (each width change reloads), `fullBanner`/`leaderboard` on tablets, no platform-view crash when banners are replaced or retried.
3. **Native:** clipping of the small/medium templates at 120/320 dp and custom `height`/`maxWidth` on various screens.
4. **Full-screen:** real callback ordering (including whether a reward is ever reported after dismissal), activity recreation, app-open integration with your own lifecycle logic, spinner overlay behaviour.
5. **Retry:** `retryFailedAds` after airplane mode is turned off.
6. Use Google's sample ad units and test devices only; never click real ads.

## 7. Remaining issues
* L5 (frequency caps, app-open triggers) and L10 (Built-in Kotlin warning) are intentionally not addressed.
* Automatic retries do not exist by design; apps call `retryFailedAds`.
* Library handling of existing ads after privacy-options changes is its own conservative policy, not an explicit Google requirement.
* Sources read for banner/UMP behaviour (2026-10-16): the AdMob Flutter guides for UMP privacy, collapsible, inline adaptive and fixed-size banners, and native templates.

## 8. Android device test (2026-10-16)

Device: Xiaomi/Poco **M2007J20CG**, Android 12 (API 31), 1080x2400, debug build of the example, Google sample app ids and test ad units only, `AdsStatus.hybrid`. Consent tests used a debug EEA geography with the phone registered as a UMP test device through `--dart-define` values (no test-device id is committed). Evidence is from `adb logcat` and `screencap` taken during the run.

Who did what: I (the assistant) built, installed, launched, tapped through the example via `adb input`, and read logs and screenshots. You performed the consent form choices, rotation, and the airplane-mode changes. Taps/touch events not issued by my adb commands appeared in the touch log while you used the phone; I did not attribute them to anyone and no result depends on them.

| # | Scenario | Result | Evidence / fixes |
|---|---|---|---|
| 1 | Start-up, managed consent, no region | Passed | `gdprApplies=0`, `adsAvailable=true`, `whenReady=true`, SDK initialized; no exceptions |
| 2 | Normal anchored banner | Passed | Test ad at the bottom, SDK height, no overflow |
| 3 | Collapsible banner, bottom | Passed after fix | First run drew the banner mid-screen (M12). After the fix: expanded overlay anchored to the bottom edge, collapses to a bar at the bottom |
| 4 | Collapsible banner, top | Passed | Expanded overlay below the app bar, collapsed bar at the top |
| 5 | Inline adaptive in a scrolling list | Passed | Loaded at item 5 with the SDK's platform height (differed between ads), survived scrolling; reloaded once on rotation; an ad that scrolled out and back was requested again (lazy-list behaviour) |
| 6 | Inline adaptive, rotation portrait -> landscape -> portrait | Passed | One request per rotation, full-width container, no overflow. The SDK letterboxes the 468x60 test creative with black side bars |
| 7 | Fixed banners 320x50 and 300x250 | Passed | Exact sizes (position issue was the example page shrink-wrapping its Column; example fixed) |
| 8 | Fixed `fullBanner` / `leaderboard` | Not tested | Tablet-only sizes; phone is too narrow for leaderboard; pending on a tablet |
| 9 | Small native ad | Passed | Fully visible at 120 dp; Google's native ad validator reported no implementation issues |
| 10 | Medium native ad | Failed, fixed, re-passed on one phone | 320 dp clipped the call-to-action (M11); with the width-based default (about 349-361 dp here) the button shows fully. Other screen sizes not tested |
| 11 | Navigation away/back during banner loading | Passed | Six rapid enter/exit cycles, no exceptions, banner then loaded |
| 12 | Interstitial, app open, rewarded, rewarded interstitial | Passed | Each loaded (preloaded or on demand) and showed; each dismissal produced exactly one success/dismissed log |
| 13 | Rapid "request all four" | Passed | One ad shown; the others logged `Another full-screen ad is already loading or showing.` |
| 14 | Reward delivery | Passed (reward path) | Rewarded and rewarded interstitial each logged `User rewarded` exactly once, before `dismissed`; also exactly once when the app was backgrounded during the ad and resumed |
| 15 | Rewarded early dismissal (before reward) | Not tested | The sample rewarded video cannot be closed with Back or an X before the reward, so a dismissal-without-reward could not be produced on the device (covered by mocked tests only) |
| 16 | Background/resume during a rewarded ad | Passed | Ad state preserved, single reward, single dismissed |
| 17 | Managed consent form (EEA debug, consent reset) | Passed | Form appeared on top of the running app; `Ads available: false` while open; start-up not blocked |
| 18 | "Do not consent" | Passed | UMP `CONSENT_SIGNAL_SUFFICIENT`, `canRequestAds=true`; library state matched (`adsAvailable=true`, `whenReady=true`, `privacyOptionsRequired=true`). Declining did not block ads |
| 19 | Privacy settings tile opens the form | Passed | Tile appeared after consent; form opened (loaded and displayed) |
| 20 | All options off via Manage options, then relaunch | Passed (outcome recorded) | Vendor consents all zero, still `canRequestAds=true`, no form on relaunch, `adsAvailable=true`. This did **not** produce a disallowed state |
| 21 | Consent withdrawal with cached ads / banners on screen | Not tested | UMP kept `canRequestAds=true` for every choice tried; the mocked tests cover cleanup |
| 22 | Disallowed state on the device | Passed (via offline) | Consent reset + airplane mode: `UMP consent info update failed`, `canRequestAds=false`, `adsAvailable=false`, `whenReady=false`, no native ad, `show*` reported one error, no crash |
| 23 | Recovery without restart | Passed after fix | Initially `refreshAvailability()` would not repeat the failed update (M13). After the fix, with the network back it showed the consent form; after "Consent" it returned true, the native ad loaded in place, the privacy tile appeared, and Show Interstitial worked (deferred preloads from the failed start were intentionally dropped) |
| 24 | Offline launch with stored consent | Passed | Update failed, `canRequestAds=true`, `adsAvailable=true`; native ad and three preloads failed once each without throwing |
| 25 | Retry API, offline then online | Passed | Banner: exactly one failure offline, one more per Retry tap offline, no automatic retries over 35 s; after reconnecting, **Retry failed banners** loaded the ad. **Retry failed native ad** loaded the native ad |
| 26 | Duplicate requests / stale ads after consent change | Partly tested | No duplicate requests observed in these runs; stale ads after a withdrawal were not produced (see 21) |

Other observations: AdMob banner auto-refresh requests arrived about every 70 s while a banner was displayed (SDK behaviour, no library timer). Logcat showed only unrelated system/MIUI exceptions.

Still pending after this session: iOS (everything), a tablet (fixed `fullBanner`/`leaderboard`, medium native at tablet widths), Android screen sizes other than 392 dp, dismissing a rewarded ad before the reward, consent withdrawal that actually turns `canRequestAds` false while ads are loaded, Android activity recreation, and app-open integration with real resume logic.

## 9. Android Activity recreation (device, 2026-10-16)

Tested with the developer option **Don't keep activities** (read before: `null`, i.e. off; set on by you for the tests;
you turned it off afterwards and it was confirmed as `0` at the end of the session). This destroys and recreates the Activity while the **process stays alive**
(same pid before and after, checked with `pidof`), so what was exercised is **Activity recreation with a new Flutter
engine, not process death**. Process death was not tested. The same Poco M2007J20CG, test ads only.

| Scenario | Result | Evidence |
|---|---|---|
| Home screen, Home then resume | Passed | `main()` re-ran (new `ADS whenReady` lines), native ad and privacy tile returned, no exception |
| Banner page, Home then resume (3 + 8 more cycles) | Passed 14/14 | Window focus returned each time, banner pages rebuilt from the home route |
| Banner page, first cycle | **Unexplained**: black screen | Window focus null, process alive and idle, activity record resumed, no app log lines, system log had an "Unexpected activity event" entry. Not reproduced in 14 further cycles. There is not enough evidence to attribute it to the OS or to the library; it stays open |
| Interstitial on screen, Home, resume | Partly expected loss | The SDK restored the ad screen; the old call's `onSuccess` never fired (its isolate is gone). The new engine then showed a fresh interstitial, got one `success / dismissed`, no stuck lock |
| Rewarded ad, Home at 4 s, resume after 14 s | **Known limitation** | Only "Reward showed" was logged; the reward earned while the Activity was destroyed was **not delivered**. This cannot be recovered by the library; apps should verify rewards server-side or persist a pending-action record |
| Automatic app-open ad after recreation with an SDK-restored ad on screen | Failed first, fixed, re-passed | Before: a second creative stacked on top (lifecycle was `inactive`). After the foreground rule: `Auto app open error: The app is not in the foreground`; the restored ad stayed alone on screen |
| Automatic app-open fired while backgrounded | Passed | Refused with the background error |
| **Restored interstitial visible** (cold start, app-open dismissed, interstitial shown by tapping, then Home and resume; rebuilt example with the foreground rule; run 12:48-12:50) | Passed | The recreated engine reported lifecycle `initial=inactive` and `inactive` at the automatic app-open (2 s after `whenReady`); log: `Auto app open error: The app is not in the foreground: no full-screen ad is shown.`; the screen showed the SDK-restored interstitial alone (same unicycle creative before and after, `AdActivity` focused, close button available), no second ad; same pid, 0 `FATAL EXCEPTION`. The ad was then closed |
| Crashes | None | 0 `FATAL EXCEPTION` in all recreation logs |

Not covered: leaked-platform-view proof (no leak instrumentation was used; only absence of errors and focus checks),
rewarded/interstitial callbacks that arrive while the engine is being recreated, process death.

## 10. Final diff review

Checked `git status`, `git diff`, `git diff --cached` and all new files.
- **Staged:** only the deletion of the tracked Android build report (`git rm --cached`; the file remains on disk).
- **Production ads:** no non-sample ad ids in the library, example, tests or docs (placeholders `xxxxxxxx` in the README
  only). The example uses Google's sample app ids and `AdsStatus.hybrid` with placeholder unit ids.
- **Consent reset / debug geography:** only enabled through `--dart-define` values (`UMP_RESET`, `UMP_TEST_DEVICE`,
  `UMP_EEA`, `AUTO_APP_OPEN_DELAY_MS`) that default to off; `debugResetConsent()` throws outside debug builds; the
  library ignores `consentDebugSettings` in release builds.
- **Device id / credentials / signing:** none committed; the test device's hashed id was only passed on the command line.
  No keystores or `google-services` files in the library repo.
- **Machine paths / generated files:** present only in git-ignored generated files (`Generated.xcconfig`,
  `flutter_export_environment.sh`, `ephemeral/`). Two toolchain artifacts are visible in the example: a much smaller
  `ios/Podfile.lock` (Flutter 3.44 uses Swift Package Manager for plugins) and untracked
  `example/ios/**/swiftpm/Package.resolved`; both are generated by the toolchain and left for the maintainer to decide.
- **Public API:** `sdk` and `retryRequests` are annotated `@internal`; `AdsSdk` is not exported; `AdRetryRequest` is
  exported only through `AdsManager`'s signature. Exported additions: banner enums, consent mode, readiness and retry
  members.
- **Obsolete APIs / dependencies:** the deprecated anchored-adaptive API was replaced; `plugin_platform_interface` was
  removed; no new dependency was added.
- **Lifecycle review of the latest fixes:** `Align` with size factors keeps ads from filling parents; the foreground
  wait registers/removes a lifecycle observer in a `try/finally` and cancels its timer; no leaks found by reading.
- **Comments:** earlier comment cleanup intact; only public dartdoc and directives remain in `lib/`.

## 11. Consuming-app trial (Track Recover)
See [CONSUMING_APP_TRIAL.md](CONSUMING_APP_TRIAL.md): **build-verified only** (its release APK is debug-signed and is not a production artifact); build and analysis checks passed; **not run on the phone**
because installing would have required uninstalling the Play Store build and its data.

## 12. Still pending (superseded by section 13 for iOS)
- **iOS:** all runtime behaviour (ads, UMP, ATT, scene lifecycle). Builds alone do not verify it; no iPhone was used.
- **Tablet:** fixed `fullBanner` / `leaderboard`, medium native and inline banners at tablet widths.
- **Early rewarded dismissal and consent-disallowed cleanup with ads on screen:** covered only by mocked tests; they
  could not be produced on the phone with Google's sample ads.
- **Track Recover:** device run of its real flows (needs a separate install path or your decision on replacing the Play build).
- **Unexplained black screen** (section 9) and process-death behaviour.
- **Known limitation:** rewards earned and callbacks fired while the Activity is destroyed are lost.

## 13. iOS device test (2026-10-16)

Device: **iPhone 15 Pro** (iPhone16,1), iOS 27.0.1, built with Xcode 27.1 and signed with the example project's existing team (`RNS34A392R`) and bundle id `com.example.flutterAdmobAdsManagerExample`; no signing setting was changed and no app was overwritten. Google sample app id (`ca-app-pub-3940256099942544~1458002511`) and Google sample units only; the debug log printed every unit id before any request. The Mac controlled screenshots only; **all taps were performed by the user**. Debug runs used `flutter run --debug` over the wireless connection; the offline tests used a profile build (`--dart-define=FORCE_TEST_ADS=true`) because a debug build cannot be relaunched from the Home screen and iOS must verify a new development-signed build while online before it launches offline.

| # | Scenario | Result | Evidence / fixes |
|---|---|---|---|
| 1 | Start-up, managed consent (no consent required in the user's region) | Passed | `canRequestAds=true`, `adsAvailable=true`, `whenReady=true`, SDK initialized, no form |
| 2 | Native ad validator | Failed, fixed, re-passed | The small native ad on iPhone raised "MediaView is too small for video". Cause: Google's iOS small template caps its media area at 25% of its width (`GADTSmallTemplateView.xib`), so ~99 pt at 393 pt width; a taller container cannot help (144 dp tried and reverted). Fix: on iOS below 480 pt `small` uses the medium template (`iosSmallMediaFallback`). Afterwards the validator reads "No implementation issues found" on the home page; the medium ad on the Native page also fit. The validator was never disabled (no `GADNativeAdValidatorEnabled` key) |
| 3 | Small / medium native layout | Passed | Video/image, "Ad" attribution, headline and button all inside the box for both ads; layout checked on one phone only |
| 4 | Normal anchored banner | Passed | Bottom, 393 pt wide, about 122 pt tall, home-indicator gap kept |
| 5 | Collapsible bottom: expanded, collapsed | Passed | Expanded ad grows upward from the bottom edge; collapse chevron returns to the 122 pt bar at the same bottom edge; safe area kept |
| 6 | Collapsible top: expanded, collapsed | Passed | Expanded ad starts under the app bar and grows down; collapsed bar sits directly under the app bar; content centred below |
| 7 | Inline adaptive in a list | Passed | 360 pt wide, ~249 pt tall (the example's 250 cap), no clipping; scrolling away and back gave the same ad size; no duplicate-AdWidget, disposal or platform-view messages |
| 8 | Inline adaptive rotation | Passed | Landscape: reloaded at ~820 pt wide, ~92 pt tall, no clipping, safe areas respected; portrait again: 360 pt / ~249 pt |
| 9 | Fixed banners 320x50 and 300x250 | Failed, fixed, re-passed | Exact sizes. The iOS adaptive sample unit (`...2435281174`) rendered a clipped creative at 320x50; fixed banners now use the fixed-size sample unit (`...2934735716`) in testing mode, giving the correct "Nice job!" 320x50 / 300x250 creatives |
| 10 | Interstitial | Passed | One `Interstitial success / dismissed` per show |
| 11 | App open | Passed | One `App Open success / dismissed` per show (additional callbacks in the log followed the user's extra taps) |
| 12 | Rewarded | Passed | `showed`, exactly one `User rewarded: 10 coins`, one `dismissed` each time (3 shows) |
| 13 | Rewarded interstitial | Passed | One `showed`, one reward, one `dismissed` |
| 14 | Rapid "request all four" | Passed | One ad on screen; the other three refused with `Another full-screen ad is already loading or showing.`; one dismissed callback; lock released |
| 15 | Background/resume during a rewarded ad | Passed | Ad still on screen after Home and resume, one reward, one `dismissed`, no callbacks repeated |
| 16 | Early rewarded dismissal | Not tested | The sample rewarded ad could not be closed before the reward (mocked tests only) |
| 17 | Offline launch | Passed (screenshots only) | App opened normally, "Ads available: true" from stored consent, native ad empty, no crash. No log in a standalone profile build |
| 18 | Offline interstitial request | Not verified | Home page returned with no stuck spinner; the error callback could not be observed without a log |
| 19 | Native retry after reconnecting | Passed | Offline-empty native ad loaded after **Retry failed native ad** |
| 20 | Banner retry | Not distinguished | The Normal banner loaded after reconnecting, but opening the page while online also loads a fresh ad, so the retry button's effect was not isolated |
| 21 | Managed consent form, privacy options, readiness on the **physical iPhone** | **Blocked / not tested** | The region needs no consent form. Forcing an EEA geography needs the iPhone's UMP test-device id, which iOS prints only in Xcode's console and not in the Flutter log; the ads test id (the hashed ads test id from the log) did not trigger the form. Needs the id from Xcode's console |
| 22 | Managed consent on the **iOS simulator** (iPhone 17, EEA debug geography, not the physical phone) | Passed | Form appeared over the running app (no start-up block), readiness logged only after "Do not consent": `canRequestAds=true`, `adsAvailable`, `whenReady=true`, `privacyOptionsRequired=true`; **Privacy settings** tile appeared and reopened the form; "Manage options" showed all purposes off; "Confirm choices" kept `canRequestAds=true` and no exception |
| 23 | Consent-disallowed cleanup with ads on screen (iOS) | Not tested | UMP kept `canRequestAds=true` for every choice tried |
| 24 | Android re-test of the native size change | Pending | The Poco phone was disconnected; the shared sizing change (iOS-only fallback, default heights unchanged for Android) is covered by mocked tests |
| 25 | Tablet / iPad | Not tested | No tablet available |

Not covered on iOS: ATT (the library does not request it), UIScene activity recreation equivalents, process kill, a device-based consent decline with `canRequestAds=false`.

### iOS lockfiles and Swift Package Manager files (example app)
Flutter 3.44 resolves `google_mobile_ads`, UMP and the other plugins through Swift Package Manager; CocoaPods integration only remains for the `Flutter` pod, so `example/ios/Podfile.lock` shrank to that one pod (tracked, kept as regenerated). Xcode wrote `Package.resolved` under `Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` and `Runner.xcworkspace/xcshareddata/swiftpm/`; they record the pinned native versions (Google Mobile Ads 13.11.0, UMP 3.1.0) that actually built and ran, so they are real dependency state, not cache. They are **retained (untracked, not ignored)** for the maintainer to decide whether to commit; the empty `configuration/` folders and generated `Flutter/ephemeral`, `Generated.xcconfig`, `Pods/` and `.symlinks` stay ignored by `example/ios/.gitignore`.
