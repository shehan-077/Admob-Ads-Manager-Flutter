# Flutter AdMob Ads Manager: Project Handover

**Status: v2.0.1 development milestone COMPLETE.** Monetization verification and host-app rollout are separate follow-ups.

## 1. Release record

| Item | Value |
|---|---|
| Project | Flutter AdMob Ads Manager (`admob_ads_manager`) |
| Current release | `2.0.1` |
| Previous release | `2.0.0` (commit `3fb8f7a`, tag `2.0.0`) |
| Baseline for the regression audit | `1.0.4` (commit `074abd0`, tag `1.0.4`) |
| Release commit | `b128c48fa8dee514c79655454cd665f682b011a8` |
| Release tag | `2.0.1` (annotated, points at the release commit) |
| Branch | `main` |
| Status | Committed, tagged and pushed |
| pub.dev publication | Not performed |
| Production app deployment | Not performed |

The tag `2.0.1` refers to the **release commit only**. The commit that adds this file is documentation-only and comes
after the tag; it changes no code, tests or version. Check with `git log --oneline 2.0.1..main`.

## 2. Architectural requirements (do not break)

1. **The library must NOT implement an App Open cooldown, minimum display interval or frequency cap.**
2. **The host application controls App Open frequency and cooldowns** (and all other full-screen frequency).
3. The library **must prevent overlapping full-screen ads** (one presented ad at a time, any format).
4. **UMP consent is never bypassed.** Nothing is requested or shown while `canRequestAds` is false.
5. **App Open (any full-screen) ads start only while the app lifecycle is `resumed`.**
6. Cache expiry (1 h; 4 h for App Open) is a freshness rule, not a display cooldown.
7. Recovery throttling (`recoveryInterval`) limits consent and retry *requests*; it must never become a limit on how
   often the host may show an ad.
8. Reward callbacks stay accurate: `onRewarded` fires only from the SDK's reward callback, once per ad.

## 3. Background

2.0.0 added managed UMP consent, new banner types, the retry API and lifecycle fixes. After upgrading, AdMob
impressions reportedly fell. A read-only audit (1.0.4 vs 2.0.0) found code-level paths that lose ad opportunities;
2.0.1 addresses them. Earlier history (audit, device tests, iOS notes) is kept in `docs/AD_LIBRARY_AUDIT.md` and
`docs/CONSUMING_APP_TRIAL.md`; `CHANGELOG.md` has per-release detail.

## 4. What 2.0.1 changed

Implemented in `lib/src/ads_manager.dart`, `lib/src/banner_ads_widget.dart`, `lib/src/native_ads_widget.dart`,
`lib/src/loading_overlay.dart`:

- **Consent timing:** `show*` made while the managed consent flow runs waits up to `consentWait`, then proceeds or
  reports exactly one error. `init()` still returns before the flow completes.
- **Consent update timeout:** a hung consent update fails after `consentUpdateTimeout` and stays recoverable.
- **Offline consent recovery:** after a failed update, a later `show*`, `preLoad`, banner/native widget or app resume
  retries it, at most once per `recoveryInterval`. `refreshAvailability()` works at any time.
- **Pending preload preservation:** preload intent is kept (a set capped at 64 slots) and resumed after recovery or a
  consent change.
- **Lock separation:** loading and presenting are separate. The presentation lock is taken in one synchronous step with
  the cached ad. A request that finds another ad showing, or was overtaken while loading, is refused (nothing queued)
  and its loaded ad stays cached.
- **Duplicate presentation prevention:** same-slot requests cannot present one ad twice; the loading spinner is
  reference-counted.
- **Presentation exceptions:** an exception while presenting disposes the ad, releases the lock and reports once.
- **Show-start watchdog:** an ad that never reports showing, dismissal or failure is failed after `showStartTimeout`;
  an ad that did start showing is never released by a timer.
- **Lifecycle:** `inactive`, `hidden` and `paused` wait up to `foregroundWait` for `resumed`; moving away again, a
  timeout, or `detached` refuses. The error names the lifecycle state.
- **Banner/native:** widgets built while ads are unavailable trigger recovery; failed widgets retry once per resume
  (spaced by `recoveryInterval`). The large anchored adaptive banner size from 2.0.0 is kept.
- **Transient consent errors:** a `canRequestAds()` platform error no longer clears cached ads or visible banners.
- **Diagnostics:** debug-only logs with an operation id (`op<N> <format>#<index>`); nothing in release builds.

### Configuration defaults (verified against `lib/src/ads_manager.dart`)

| Field | Default | Purpose |
|---|---|---|
| `consentWait` | 3 s | Bounded wait of `show*` for the consent flow |
| `consentUpdateTimeout` | 30 s | Consent info update time limit |
| `recoveryInterval` | 30 s | Spacing of consent recovery and resume retries |
| `showStartTimeout` | 10 s | Watchdog for an ad that never reports showing |
| `foregroundWait` | 2 s | Wait for `resumed` (unchanged from 2.0.0) |
| `retryFailedAdsOnResume` | `true` | Retry failed banner/native widgets on resume |
| `loadTimeout` | 15 s | Ad request timeout (unchanged) |
| `sdkInitTimeout` | 30 s | SDK init timeout (unchanged) |

## 5. Automated validation

- `flutter analyze`: clean (library and example). `dart format`: clean.
- `flutter test`: **168 passed, 0 failed** (134 before 2.0.1, 34 new).
- Example debug APK (`flutter build apk --debug` in `example/`): built.
- Test files: `test/ads_manager_test.dart`, `test/banner_test.dart`, `test/readiness_rewards_test.dart`,
  `test/impression_reliability_test.dart` (new), fakes in `test/support/fakes.dart`.
- Commands: `flutter pub get`, `flutter analyze`, `flutter test`, `cd example && flutter build apk --debug`.

All tests use fake SDKs. They show correct behaviour, not revenue improvement.

## 6. Physical Android validation

Device: Xiaomi POCO X3 NFC (M2007J20CG), Android 12 / API 31. Google's **test ad units only** (the example uses
`AdsStatus.hybrid` with placeholder ids); real SDK impression callbacks were observed (`op<N> impression`) for test
ads. Consent and app data were not reset.

**21 scenarios: 17 PASS, 4 NOT VERIFIED, 0 confirmed library defects, 0 fatal crashes.**

Verified (PASS): cold-start App Open (requested while consent was running, then shown); warm-start App Open;
`inactive`/`hidden`/`paused` to `resumed` transitions; rapid background/foreground transitions (one ad, never shown
while backgrounded); App Open automatic preload after dismissal; no overlapping full-screen ads; no built-in App Open
cooldown (back-to-back requests honoured); error callbacks (busy, not-in-foreground, offline load error, once each);
a ready ad not blocked by an unrelated load; interstitial show and re-preload; rewarded callbacks and reward once;
rewarded interstitial callbacks and reward once; all banner types (normal, collapsible, collapsible top, inline,
fixed); native small and medium; orientation, navigation and rebuild behaviour (no duplicate requests); offline banner
failure with one request and no loop, then recovery on resume; retry spacing; offline start with stored consent, then
on-demand load after connectivity returned.

## 7. Unverified scenarios (not passed)

1. Offline first launch **without** stored consent (covered only by mocked tests).
2. Real first-time or EEA consent form behaviour (the test device's region showed no form).
3. Automatic preload-failure recovery beyond on-demand loading (failed preloads are not retried automatically; the next
   `show*` loads on demand).
4. Android Activity recreation and the show-start watchdog on hardware.

Observations (documented limitations, **not** confirmed defects):

- A slow consent flow can exceed the default 3 s `consentWait` (about 3 to 4 s was measured on the test device).
- Any `resumed` event, including the one after an ad is dismissed, uses the 30 s resume-retry slot, so a banner retry
  shortly after an ad dismissal may be suppressed.
- Banner/native diagnostics are less detailed than full-screen diagnostics (full-screen operations carry an op id).
- Host apps must integrate `whenReady()`, the consent mode, error handling and recovery correctly.

## 8. Host application integration checklist

- [ ] Depend on `2.0.1` (`google_mobile_ads` ^9.1.0, Flutter >= 3.38.1).
- [ ] Choose `AdsConsentMode.managed` (default) or `external` if the app already runs UMP; never run two flows.
- [ ] Use `whenReady()` with your own bound before automatic ads such as a splash App Open; continue without an ad on
      timeout.
- [ ] `preLoad` after initialization (calls made earlier are remembered).
- [ ] Trigger App Open from your own lifecycle logic; the library only starts ads while `resumed`.
- [ ] Implement your own App Open cooldown and frequency caps (the library has none).
- [ ] Handle every rejected request in `onError`; keep essential flows (navigation, purchases) in the error branch.
- [ ] Offline: call `refreshAvailability()` on connectivity return if you want an immediate attempt; otherwise recovery
      happens on later requests or resume.
- [ ] Banner/native: failed widgets retry once per resume; use `retryFailedAds()` for explicit retries.
- [ ] Do not fire duplicate show requests for the same placement.
- [ ] Test on physical Android devices with test ads before release.
- [ ] Validate on iOS before any iOS production rollout (iOS runtime tests of 2.0.1 were not performed).

## 9. Production monetization monitoring

The reason for 2.0.1 was a reported fall in AdMob impressions after 2.0.0. Code-level reliability issues were found and
fixed, and automated and Android device tests pass. **No production revenue improvement has been verified, and the
revenue issue must not be called resolved.** After a controlled host-app rollout, compare AdMob requests, matched
requests, impressions, show rate, eCPM and impressions per active user against the previous version.

## 10. Final status and how to resume

**Flutter AdMob Ads Manager v2.0.1: development milestone COMPLETE.** The patch is implemented, the `2.0.1` tag exists,
automated validation is complete, Android device validation is complete with the limits above, and no further library
changes are currently required. Open follow-ups: host-app integration, AdMob monitoring, iOS validation, and the four
unverified scenarios if they matter.

To resume without repeating the audit: read sections 2, 4 and 7 here, then `CHANGELOG.md` (2.0.1). Run
`flutter analyze && flutter test`. Use `git log --oneline 1.0.4..main` for history. Start new work from the unverified
list or from production data, not from a new full audit.
