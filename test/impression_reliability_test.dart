import 'dart:async';

import 'package:admob_ads_manager/admob_ads_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'support/fakes.dart';

/// Regression tests for the 2.0.1 impression-reliability changes: consent
/// start-up timing, offline recovery, load/present separation, lifecycle
/// handling and error paths. All SDK interaction is faked.
class _CallbackThrowingInterstitial extends FakeInterstitial {
  @override
  set fullScreenContentCallback(
    FullScreenContentCallback<InterstitialAd>? value,
  ) => throw StateError('cannot attach');
}

void main() {
  final manager = AdsManager.instance;
  late Harness h;
  late DateTime now;

  Future<void> start({
    Harness? harness,
    AdsConsentMode mode = AdsConsentMode.managed,
  }) async {
    h = harness ?? Harness();
    manager.resetForTesting(sdk: h.sdk);
    now = DateTime(2026, 1, 1);
    manager.clock = () => now;
    await manager.init(
      ids: testIds,
      status: AdsStatus.enabled,
      consentMode: mode,
    );
  }

  Harness offlineHarness() => Harness()
    ..updateError = FormError(errorCode: 1, message: 'offline')
    ..canRequest = false;

  void goOnline() {
    h.updateError = null;
    h.canRequest = true;
  }

  void lifecycle(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  group('consent start-up timing', () {
    testWidgets('init then an immediate show waits for consent, then shows', (
      tester,
    ) async {
      await start(harness: Harness()..formGate = Completer<FormError?>());
      final ctx = await pumpHost(tester);
      final ad = FakeAppOpen();
      h.onAppOpen = (cb) => cb.onAdLoaded(ad);
      final rec = Recorder();

      final show = manager.showAppOpen(ctx, 0, rec);
      await tester.pump(const Duration(seconds: 1));
      expect(h.appOpenRequests, 0, reason: 'no request before consent');

      h.formGate!.complete(null);
      await show;
      expect(h.appOpenRequests, 1);
      expect(ad.shown, 1);
      ad.dismiss();
      expect(rec.success, 1);
      expect(rec.errors, isEmpty);
    });

    testWidgets('a returning user (stored consent) shows without a form', (
      tester,
    ) async {
      await start();
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(h.consentForms, 1); // "if required": the SDK decides
      expect(h.appOpenRequests, 1);
      expect(rec.errors, isEmpty);
    });

    testWidgets('consent denied: exactly one error, no request', (
      tester,
    ) async {
      final harness = Harness()..formGate = Completer<FormError?>();
      await start(harness: harness);
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      final show = manager.showInterstitial(ctx, 0, rec);
      await tester.pump(const Duration(milliseconds: 100));
      h.canRequest = false;
      h.formGate!.complete(null);
      await show;
      expect(rec.errors, hasLength(1));
      expect(rec.success, 0);
      expect(h.interstitialRequests, 0);
    });

    testWidgets('a flow that outlasts consentWait yields one error', (
      tester,
    ) async {
      await start(harness: Harness()..formGate = Completer<FormError?>());
      manager.consentWait = const Duration(seconds: 1);
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      final show = manager.showInterstitial(ctx, 0, rec);
      await tester.pump(const Duration(seconds: 2));
      await show;
      expect(rec.errors, hasLength(1));
      expect(h.interstitialRequests, 0);

      h.formGate!.complete(null);
      await manager.consentReady;
      await manager.showInterstitial(ctx, 0, rec);
      expect(h.interstitialRequests, 1, reason: 'the next call works');
    });

    test('a hanging consent update times out and stays recoverable', () async {
      final harness = Harness()..canRequest = false;
      harness.sdk.requestConsentInfoUpdate = (_) =>
          Completer<FormError?>().future;
      h = harness;
      manager.resetForTesting(sdk: h.sdk);
      manager.consentUpdateTimeout = const Duration(milliseconds: 50);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      expect(await manager.whenReady(), isFalse);
      expect(manager.consentInProgress, isFalse);
    });

    test('init keeps returning before the form completes', () async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      expect(manager.consentInProgress, isTrue);
      h.formGate!.complete(null);
      expect(await manager.whenReady(), isTrue);
    });

    testWidgets('external mode never waits for consent', (tester) async {
      await start(mode: AdsConsentMode.external);
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(h.consentUpdates, 0);
      expect(h.interstitialRequests, 1);
    });
  });

  group('offline initialization recovery', () {
    testWidgets('a later show recovers once the network is back', (
      tester,
    ) async {
      await start(harness: offlineHarness());
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final rec = Recorder();

      // Still within the spacing window: no repeated consent request.
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
      expect(h.consentUpdates, 1);
      expect(h.interstitialRequests, 0, reason: 'never without consent');

      goOnline();
      now = now.add(const Duration(seconds: 31));
      await manager.showInterstitial(ctx, 0, rec);
      expect(h.consentUpdates, 2);
      expect(h.interstitialRequests, 1);
      expect(manager.adsAvailable.value, isTrue);
    });

    testWidgets('preload intent survives and resumes after recovery', (
      tester,
    ) async {
      await start(harness: offlineHarness());
      await manager.consentReady;
      await manager.preLoad(AdsUnit.interstitial, 0);
      await manager.preLoad(AdsUnit.interstitial, 0);
      await manager.preLoad(AdsUnit.appOpen, 0);
      expect(h.totalRequests, 0);

      goOnline();
      now = now.add(const Duration(seconds: 31));
      expect(await manager.refreshAvailability(), isTrue);
      await tester.pump();
      expect(h.interstitialRequests, 1, reason: 'deduplicated slot');
      expect(h.appOpenRequests, 1);
    });

    testWidgets('returning to the foreground is a recovery opportunity', (
      tester,
    ) async {
      await start(harness: offlineHarness());
      await manager.consentReady;
      await manager.preLoad(AdsUnit.rewarded, 0);
      goOnline();
      now = now.add(const Duration(seconds: 31));
      lifecycle(tester, AppLifecycleState.resumed);
      await manager.consentReady;
      await tester.pump();
      expect(manager.adsAvailable.value, isTrue);
      expect(h.rewardedRequests, 1);
    });

    testWidgets('repeated failures are spaced and never poison the state', (
      tester,
    ) async {
      await start(harness: offlineHarness());
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      for (var i = 0; i < 5; i++) {
        await manager.showInterstitial(ctx, 0, rec);
      }
      expect(h.consentUpdates, 1, reason: 'spaced by recoveryInterval');

      now = now.add(const Duration(seconds: 31));
      await manager.showInterstitial(ctx, 0, rec);
      expect(h.consentUpdates, 2);
      expect(h.interstitialRequests, 0);

      goOnline();
      now = now.add(const Duration(seconds: 31));
      await manager.showInterstitial(ctx, 0, rec);
      expect(h.interstitialRequests, 1);
    });

    testWidgets('concurrent requests share one recovery attempt', (
      tester,
    ) async {
      await start(harness: offlineHarness());
      await manager.consentReady;
      goOnline();
      now = now.add(const Duration(seconds: 31));
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      await Future.wait([
        manager.showInterstitial(ctx, 0, rec),
        manager.showAppOpen(ctx, 0, rec),
        manager.preLoad(AdsUnit.rewarded, 0),
      ]);
      expect(h.consentUpdates, 2, reason: 'one start-up + one recovery');
    });

    testWidgets('never loads or shows while canRequestAds is false', (
      tester,
    ) async {
      await start(harness: Harness()..canRequest = false);
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(h.totalRequests, 0);
      expect(rec.errors, hasLength(1));
    });

    testWidgets('a banner built while unavailable loads after recovery', (
      tester,
    ) async {
      await start(harness: offlineHarness());
      await manager.consentReady;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdContainer(index: 0))),
      );
      await tester.pump();
      expect(h.banners, isEmpty);

      goOnline();
      now = now.add(const Duration(seconds: 31));
      expect(await manager.refreshAvailability(), isTrue);
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
    });

    testWidgets('a canRequestAds error never withdraws ads already usable', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(manager.adsAvailable.value, isTrue);

      h.canRequestThrows = true;
      await manager.refreshAvailability();
      expect(manager.adsAvailable.value, isTrue);
      h.canRequestThrows = false;

      final ctx = await pumpHost(tester);
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(h.interstitialRequests, 1, reason: 'the cached ad was kept');
    });
  });

  group('failed banner / native retry on resume', () {
    testWidgets('a failed banner is retried once per resume interval', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdContainer(index: 0))),
      );
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
      h.banners.single.fireFailed();

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(2));
      h.banners.last.fireFailed();

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(h.banners, hasLength(2), reason: 'inside recoveryInterval');

      now = now.add(const Duration(seconds: 31));
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(3));
    });

    testWidgets('the resume retry can be switched off', (tester) async {
      await start();
      manager.retryFailedAdsOnResume = false;
      await manager.consentReady;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdContainer(index: 0))),
      );
      await tester.pump();
      await tester.pump();
      h.banners.single.fireFailed();
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
    });

    testWidgets('a loaded banner is not reloaded on resume', (tester) async {
      await start();
      await manager.consentReady;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdContainer(index: 0))),
      );
      await tester.pump();
      await tester.pump();
      h.banners.single.fireLoaded();
      await tester.pump();
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(h.banners, hasLength(1));
    });
  });

  group('full-screen coordination', () {
    testWidgets('a ready ad shows while another format is still loading', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final open = FakeAppOpen();
      h.onAppOpen = (cb) => cb.onAdLoaded(open);
      await manager.preLoad(AdsUnit.appOpen, 0);

      late InterstitialAdLoadCallback pending;
      h.onInterstitial = (cb) => pending = cb;
      final interstitialRec = Recorder();
      final slow = manager.showInterstitial(ctx, 0, interstitialRec);
      await tester.pump();

      final openRec = Recorder();
      await manager.showAppOpen(ctx, 0, openRec);
      expect(open.shown, 1, reason: 'not blocked by the unrelated load');

      // The load finishes while the app-open ad is on screen: refused, not
      // queued, and the loaded ad is kept.
      final loaded = FakeInterstitial();
      pending.onAdLoaded(loaded);
      await slow;
      expect(interstitialRec.errors, hasLength(1));
      expect(loaded.shown, 0);
      expect(loaded.disposed, 0);

      open.dismiss();
      expect(openRec.success, 1);
      await manager.showInterstitial(ctx, 0, interstitialRec);
      expect(loaded.shown, 1, reason: 'the cached ad is usable later');
      expect(h.interstitialRequests, 1);
    });

    testWidgets('an ad is not shown after another ad overtook its load', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      late InterstitialAdLoadCallback pending;
      h.onInterstitial = (cb) => pending = cb;
      final rec = Recorder();
      final slow = manager.showInterstitial(ctx, 0, rec);
      await tester.pump();

      final open = FakeAppOpen();
      h.onAppOpen = (cb) => cb.onAdLoaded(open);
      final openRec = Recorder();
      await manager.showAppOpen(ctx, 0, openRec);
      open.dismiss(); // the other ad is already gone

      final loaded = FakeInterstitial();
      pending.onAdLoaded(loaded);
      await slow;
      expect(loaded.shown, 0, reason: 'the placement opportunity has passed');
      expect(rec.errors, hasLength(1));
    });

    testWidgets('two requests for the same slot never present one ad twice', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      late InterstitialAdLoadCallback pending;
      h.onInterstitial = (cb) => pending = cb;
      final first = Recorder();
      final second = Recorder();
      final a = manager.showInterstitial(ctx, 0, first);
      await tester.pump();
      await manager.showInterstitial(ctx, 0, second);
      expect(second.errors, hasLength(1));

      final ad = FakeInterstitial();
      pending.onAdLoaded(ad);
      await a;
      expect(ad.shown, 1);
      ad.dismiss();
      expect(first.success, 1);
      expect(second.success, 0);
      await tester.pump();
      pending.onAdLoaded(FakeInterstitial()); // completes the re-preload
    });

    testWidgets('a preload never blocks a ready ad', (tester) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final open = FakeAppOpen();
      h.onAppOpen = (cb) => cb.onAdLoaded(open);
      await manager.preLoad(AdsUnit.appOpen, 0);
      h.onInterstitial = (cb) {};
      unawaited(manager.preLoad(AdsUnit.interstitial, 0));
      await tester.pump();
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(open.shown, 1);
      await tester.pump(const Duration(seconds: 16)); // the preload times out
    });

    testWidgets('overlapping loads keep the spinner until the last ends', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      late InterstitialAdLoadCallback i;
      late RewardedAdLoadCallback r;
      h.onInterstitial = (cb) => i = cb;
      h.onRewarded = (cb) => r = cb;
      final a = manager.showInterstitial(ctx, 0, Recorder());
      final b = manager.showRewarded(ctx, 0, RewardedCallbacks());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      i.onAdLoaded(FakeInterstitial());
      await a;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      r.onAdLoaded(FakeRewarded());
      await b;
    });

    testWidgets('an exception while presenting releases everything', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final bad = _CallbackThrowingInterstitial();
      h.onInterstitial = (cb) => cb.onAdLoaded(bad);
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
      expect(bad.disposed, 1);

      h.onInterstitial = (cb) => cb.onAdLoaded(FakeInterstitial());
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(1), reason: 'the lock was released');
    });

    testWidgets('an ad that never reports showing fails and frees the lock', (
      tester,
    ) async {
      await start();
      manager.showStartTimeout = const Duration(seconds: 5);
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final ad = FakeAppOpen()..reportShowed = false;
      final next = FakeAppOpen();
      h.onAppOpen = (cb) => cb.onAdLoaded(ad);
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(ad.shown, 1);
      h.onAppOpen = (cb) => cb.onAdLoaded(next); // the automatic re-preload

      await tester.pump(const Duration(seconds: 6));
      expect(rec.errors, hasLength(1));
      expect(rec.success, 0);
      expect(ad.disposed, 1);

      // A late callback of the old ad cannot affect anything.
      ad.dismiss();
      expect(rec.success, 0);
      expect(rec.errors, hasLength(1));

      await manager.showAppOpen(ctx, 0, rec);
      expect(next.shown, 1);
    });

    testWidgets('a visible ad is never released by a timer', (tester) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final ad = FakeAppOpen();
      h.onAppOpen = (cb) => cb.onAdLoaded(ad);
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      await tester.pump(const Duration(minutes: 10));
      expect(rec.errors, isEmpty);
      expect(ad.disposed, 0);

      final other = Recorder();
      await manager.showInterstitial(ctx, 0, other);
      expect(other.errors, hasLength(1), reason: 'overlap protection holds');
      ad.dismiss();
      expect(rec.success, 1);
    });

    testWidgets('no frequency limit: back-to-back requests are honoured', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      for (var i = 0; i < 3; i++) {
        final ad = FakeAppOpen();
        h.onAppOpen = (cb) => cb.onAdLoaded(ad);
        await manager.showAppOpen(ctx, 0, rec);
        expect(ad.shown, 1);
        ad.dismiss();
      }
      expect(rec.success, 3);
      expect(rec.errors, isEmpty);
    });

    testWidgets('rewarded callbacks are unchanged by the new pipeline', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      final ad = FakeRewarded();
      h.onRewarded = (cb) => cb.onAdLoaded(ad);
      var showed = 0, rewarded = 0, dismissed = 0;
      await manager.showRewarded(
        ctx,
        0,
        RewardedCallbacks(
          onShowed: () => showed++,
          onRewarded: (_) => rewarded++,
          onDismissed: () => dismissed++,
        ),
      );
      ad.reward();
      ad.reward();
      ad.dismiss();
      expect([showed, rewarded, dismissed], [1, 1, 1]);
    });
  });

  group('lifecycle transitions', () {
    testWidgets('paused that resumes within the wait proceeds', (tester) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      lifecycle(tester, AppLifecycleState.paused);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      final rec = Recorder();
      final show = manager.showAppOpen(ctx, 0, rec);
      await tester.pump(const Duration(milliseconds: 200));
      lifecycle(tester, AppLifecycleState.hidden);
      await tester.pump(const Duration(milliseconds: 100));
      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 100));
      lifecycle(tester, AppLifecycleState.resumed);
      await show;
      expect(rec.errors, isEmpty);
      expect(h.appOpenRequests, 1);
    });

    testWidgets('a genuinely backgrounded app is refused with the state', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      lifecycle(tester, AppLifecycleState.paused);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      final rec = Recorder();
      final show = manager.showAppOpen(ctx, 0, rec);
      await tester.pump(const Duration(seconds: 3));
      await show;
      expect(rec.errors.single, contains('foreground'));
      expect(rec.errors.single, contains('paused'));
      expect(h.totalRequests, 0);
    });

    testWidgets('detached is refused at once', (tester) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      lifecycle(tester, AppLifecycleState.detached);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
    });

    testWidgets('leaving again while waiting is refused', (tester) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      lifecycle(tester, AppLifecycleState.inactive);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      final rec = Recorder();
      final show = manager.showAppOpen(ctx, 0, rec);
      await tester.pump(const Duration(milliseconds: 100));
      lifecycle(tester, AppLifecycleState.hidden);
      await show;
      expect(rec.errors, hasLength(1));
    });

    testWidgets('rapid transitions end with one correct decision', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.paused);
      lifecycle(tester, AppLifecycleState.hidden);
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(rec.errors, isEmpty);
      expect(h.appOpenRequests, 1);
    });

    testWidgets('a state that never resumes (restored ad on top) is refused', (
      tester,
    ) async {
      await start();
      await manager.consentReady;
      final ctx = await pumpHost(tester);
      lifecycle(tester, AppLifecycleState.inactive);
      addTearDown(() => lifecycle(tester, AppLifecycleState.resumed));
      final rec = Recorder();
      final show = manager.showAppOpen(ctx, 0, rec);
      await tester.pump(const Duration(seconds: 3));
      await show;
      expect(rec.errors, hasLength(1));
      expect(h.totalRequests, 0);
    });
  });
}
