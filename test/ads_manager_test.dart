import 'dart:async';

import 'package:admob_ads_manager/admob_ads_manager.dart';
import 'package:admob_ads_manager/src/ad_preload_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'support/fakes.dart';

void main() {
  final manager = AdsManager.instance;
  late Harness h;

  Future<void> setUpManager({
    AdsStatus status = AdsStatus.enabled,
    AdsConsentMode mode = AdsConsentMode.managed,
    Harness? harness,
  }) async {
    h = harness ?? Harness();
    manager.resetForTesting(sdk: h.sdk);
    await manager.init(ids: testIds, status: status, consentMode: mode);
    await manager.consentReady;
  }

  group('AdPreloadCache', () {
    test('take hands over ownership without disposing', () {
      final cache = AdPreloadCache();
      final ad = FakeInterstitial();
      cache.set(AdsUnit.interstitial, 0, ad);
      expect(cache.take<InterstitialAd>(AdsUnit.interstitial, 0), same(ad));
      expect(ad.disposed, 0);
      expect(cache.contains(AdsUnit.interstitial, 0), isFalse);
    });

    test('remove disposes exactly once', () {
      final cache = AdPreloadCache();
      final ad = FakeInterstitial();
      cache.set(AdsUnit.interstitial, 0, ad);
      cache.remove(AdsUnit.interstitial, 0);
      cache.remove(AdsUnit.interstitial, 0);
      expect(ad.disposed, 1);
    });

    test('re-setting the same ad does not dispose it', () {
      final cache = AdPreloadCache();
      final ad = FakeInterstitial();
      cache.set(AdsUnit.interstitial, 0, ad);
      cache.set(AdsUnit.interstitial, 0, ad);
      expect(ad.disposed, 0);
    });

    test('expired ads are evicted, disposed and never returned', () {
      var now = DateTime(2026);
      final cache = AdPreloadCache(now: () => now);
      final inter = FakeInterstitial();
      final open = FakeAppOpen();
      cache.set(AdsUnit.interstitial, 0, inter);
      cache.set(AdsUnit.appOpen, 0, open);

      now = now.add(const Duration(minutes: 61));
      expect(cache.get<InterstitialAd>(AdsUnit.interstitial, 0), isNull);
      expect(inter.disposed, 1);
      expect(cache.get<AppOpenAd>(AdsUnit.appOpen, 0), same(open));

      now = now.add(const Duration(hours: 3));
      expect(cache.get<AppOpenAd>(AdsUnit.appOpen, 0), isNull);
      expect(open.disposed, 1);
    });
  });

  group('ad unit ids', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('testing mode returns Google test ids on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await setUpManager(status: AdsStatus.testing);
      expect(
        manager.getAdUnitId(AdsUnit.interstitial, 0),
        'ca-app-pub-3940256099942544/1033173712',
      );
      expect(
        manager.getBannerAdUnitId(0, type: BannerAdsType.collapsible),
        'ca-app-pub-3940256099942544/2014213617',
      );
      expect(
        manager.getBannerAdUnitId(0, type: BannerAdsType.inlineAdaptive),
        'ca-app-pub-3940256099942544/6300978111',
      );
    });

    test('testing mode returns Google test ids on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await setUpManager(status: AdsStatus.testing);
      expect(
        manager.getBannerAdUnitId(0, type: BannerAdsType.collapsible),
        'ca-app-pub-3940256099942544/8388050270',
      );
      expect(
        manager.getAdUnitId(AdsUnit.native, 0),
        'ca-app-pub-3940256099942544/3986624511',
      );
    });

    test('iOS fixed banners use the fixed-size sample banner unit', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await setUpManager(status: AdsStatus.testing);
      expect(
        manager.getBannerAdUnitId(0, type: BannerAdsType.fixed),
        'ca-app-pub-3940256099942544/2934735716',
      );
      expect(
        manager.getBannerAdUnitId(0, type: BannerAdsType.normal),
        'ca-app-pub-3940256099942544/2435281174',
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        manager.getBannerAdUnitId(0, type: BannerAdsType.fixed),
        'ca-app-pub-3940256099942544/6300978111',
      );
    });

    test('testing mode never falls back to production ids', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await setUpManager(status: AdsStatus.testing);
      expect(
        () => manager.getAdUnitId(AdsUnit.interstitial, 0),
        throwsUnsupportedError,
      );
      expect(
        () => manager.getBannerAdUnitId(0, type: BannerAdsType.collapsible),
        throwsUnsupportedError,
      );
    });

    test('indexes wrap, negative indexes are rejected', () async {
      await setUpManager();
      expect(manager.getAdUnitId(AdsUnit.interstitial, 3), 'int1');
      expect(manager.getBannerAdUnitId(2), 'ban0');
      expect(
        () => manager.getAdUnitId(AdsUnit.interstitial, -1),
        throwsArgumentError,
      );
    });

    test('AdMobIds.forPlatform picks the platform ids', () {
      final android = testIds;
      final ios = AdMobIds.single(
        appId: 'i',
        interstitialId: 'i',
        bannerId: 'i',
        appOpenId: 'i',
        rewardedId: 'i',
        nativeId: 'i',
        rewardedIntId: 'i',
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AdMobIds.forPlatform(android: android, ios: ios), same(ios));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AdMobIds.forPlatform(android: android, ios: ios), same(android));
    });
  });

  group('loading', () {
    test('preLoad swallows load failures (offline start-up)', () async {
      await setUpManager();
      h.onInterstitial = (cb) =>
          cb.onAdFailedToLoad(LoadAdError(2, 'd', 'network', null));
      await manager.preLoad(AdsUnit.interstitial, 0);
    });

    test('concurrent preLoad calls share one request', () async {
      await setUpManager();
      final pending = <InterstitialAdLoadCallback>[];
      h.onInterstitial = pending.add;
      final a = manager.preLoad(AdsUnit.interstitial, 0);
      final b = manager.preLoad(AdsUnit.interstitial, 0);
      await Future<void>.delayed(Duration.zero);
      expect(h.interstitialRequests, 1);
      pending.single.onAdLoaded(FakeInterstitial());
      await Future.wait([a, b]);
    });

    test('preLoad does not replace a fresh cached ad', () async {
      await setUpManager();
      await manager.preLoad(AdsUnit.interstitial, 0);
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(h.interstitialRequests, 1);
    });

    test('disabled status performs no SDK or consent work', () async {
      await setUpManager(status: AdsStatus.disabled);
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(h.initCount, 0);
      expect(h.consentUpdates, 0);
      expect(h.interstitialRequests, 0);
      expect(manager.adsAvailable.value, isFalse);
    });
  });

  group('interstitial', () {
    testWidgets('success: onSuccess exactly once, ad disposed once', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      final shown = FakeInterstitial();
      h.onInterstitial = (cb) => cb.onAdLoaded(shown);

      await manager.showInterstitial(ctx, 0, rec);
      expect(shown.shown, 1);
      shown.dismiss();
      shown.dismiss();
      await tester.pump();

      expect(rec.success, 1);
      expect(rec.errors, isEmpty);
      expect(shown.disposed, 1);
    });

    testWidgets('load failure reports exactly one error and hides spinner', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      h.onInterstitial = (cb) =>
          cb.onAdFailedToLoad(LoadAdError(3, 'd', 'no fill', null));

      await manager.showInterstitial(ctx, 0, rec);
      await tester.pump();

      expect(rec.errors, hasLength(1));
      expect(rec.success, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('overlapping show is rejected, allowed after dismissal', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final first = Recorder();
      final second = Recorder();
      final ads = <FakeInterstitial>[];
      h.onInterstitial = (cb) {
        final ad = FakeInterstitial();
        ads.add(ad);
        cb.onAdLoaded(ad);
      };

      await manager.showInterstitial(ctx, 0, first);
      await manager.showInterstitial(ctx, 0, second);
      expect(second.errors, hasLength(1));
      expect(ads.where((a) => a.shown > 0), hasLength(1));

      ads.first.dismiss();
      await tester.pump();
      await manager.showInterstitial(ctx, 0, second);
      expect(second.errors, hasLength(1));
      expect(ads.where((a) => a.shown > 0), hasLength(2));
    });

    testWidgets('failed-to-show reports once and releases the guard', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      final ad = FakeInterstitial();
      h.onInterstitial = (cb) => cb.onAdLoaded(ad);

      await manager.showInterstitial(ctx, 0, rec);
      ad.failToShow();
      ad.failToShow();
      expect(rec.errors, hasLength(1));
      expect(ad.disposed, 1);

      await manager.showInterstitial(ctx, 0, rec);
      expect(h.interstitialRequests, greaterThanOrEqualTo(2));
    });

    testWidgets('show() failure releases guard and reports', (tester) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      var first = true;
      h.onInterstitial = (cb) {
        cb.onAdLoaded(
          FakeInterstitial()..showError = first ? StateError('boom') : null,
        );
        first = false;
      };

      await manager.showInterstitial(ctx, 0, rec);
      await tester.pump();
      expect(rec.errors, hasLength(1));

      final rec2 = Recorder();
      await manager.showInterstitial(ctx, 0, rec2);
      expect(rec2.errors, isEmpty);
    });

    testWidgets('failing re-preload after dismissal is not unhandled', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeInterstitial();
      h.onInterstitial = (cb) => cb.onAdLoaded(ad);
      await manager.showInterstitial(ctx, 0, Recorder());

      h.onInterstitial = (cb) =>
          cb.onAdFailedToLoad(LoadAdError(2, 'd', 'offline', null));
      ad.dismiss();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cached ad is shown without a new request', (tester) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      await manager.preLoad(AdsUnit.interstitial, 0);
      await manager.showInterstitial(ctx, 0, Recorder());
      expect(h.interstitialRequests, 1);
    });

    testWidgets('unmounted context is reported, never a lost continuation', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      await tester.pumpWidget(const SizedBox());
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
      expect(h.interstitialRequests, 0);
    });

    testWidgets('ads disabled continues the flow immediately', (tester) async {
      await setUpManager(status: AdsStatus.disabled);
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.success, 1);
      expect(h.interstitialRequests, 0);
    });
  });

  group('timeouts and late callbacks', () {
    testWidgets(
      'late ad after timeout is cached, never shown by the old call',
      (tester) async {
        await setUpManager();
        manager.loadTimeout = const Duration(milliseconds: 50);
        final ctx = await pumpHost(tester);
        final rec = Recorder();
        late InterstitialAdLoadCallback pending;
        h.onInterstitial = (cb) => pending = cb;

        final future = manager.showInterstitial(ctx, 0, rec);
        await tester.pump(const Duration(milliseconds: 100));
        await future;
        expect(rec.errors, hasLength(1));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        final late = FakeInterstitial();
        pending.onAdLoaded(late);
        await tester.pump();
        expect(late.shown, 0);
        expect(late.disposed, 0);
        expect(rec.success, 0);
        expect(rec.errors, hasLength(1));

        final before = h.interstitialRequests;
        await manager.showInterstitial(ctx, 0, rec);
        expect(late.shown, 1);
        expect(h.interstitialRequests, before);
      },
    );

    testWidgets('a late callback never releases a newer operation\'s lock', (
      tester,
    ) async {
      await setUpManager();
      manager.loadTimeout = const Duration(milliseconds: 50);
      final ctx = await pumpHost(tester);
      final callbacks = <InterstitialAdLoadCallback>[];
      h.onInterstitial = callbacks.add;

      final recA = Recorder();
      final a = manager.showInterstitial(ctx, 0, recA);
      await tester.pump(const Duration(milliseconds: 100));
      await a;
      expect(recA.errors, hasLength(1));

      manager.loadTimeout = const Duration(seconds: 15);
      final recB = Recorder();
      final b = manager.showInterstitial(ctx, 0, recB);
      await tester.pump();
      expect(callbacks, hasLength(2));

      final lateA = FakeInterstitial();
      callbacks[0].onAdLoaded(lateA);
      await tester.pump();
      expect(lateA.shown, 0);

      final recC = Recorder();
      await manager.showInterstitial(ctx, 0, recC);
      expect(recC.errors, hasLength(1));

      final adB = FakeInterstitial();
      callbacks[1].onAdLoaded(adB);
      await b;
      expect(adB.shown + lateA.shown, 1);
      expect(recB.errors, isEmpty);
    });

    testWidgets('a stale operation cannot release a newer lock', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ads = <FakeInterstitial>[];
      h.onInterstitial = (cb) {
        final ad = FakeInterstitial();
        ads.add(ad);
        cb.onAdLoaded(ad);
      };
      await manager.showInterstitial(ctx, 0, Recorder());
      final firstAd = ads.first;

      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      await manager.consentReady;
      await manager.showInterstitial(ctx, 0, Recorder());
      final secondAd = ads.last;
      expect(secondAd.shown, 1);

      firstAd.dismiss();
      await tester.pump();

      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
    });

    testWidgets('late ad that became obsolete is disposed', (tester) async {
      await setUpManager();
      manager.loadTimeout = const Duration(milliseconds: 50);
      final ctx = await pumpHost(tester);
      late InterstitialAdLoadCallback pending;
      h.onInterstitial = (cb) => pending = cb;

      final f = manager.showInterstitial(ctx, 0, Recorder());
      await tester.pump(const Duration(milliseconds: 100));
      await f;

      h.canRequest = false;
      await manager.showPrivacyOptionsForm();
      final late = FakeInterstitial();
      pending.onAdLoaded(late);
      await tester.pump();
      expect(late.disposed, 1);
      expect(late.shown, 0);
    });

    testWidgets('preloading is not blocked by a showing fullscreen ad', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeInterstitial();
      h.onInterstitial = (cb) => cb.onAdLoaded(ad);
      await manager.showInterstitial(ctx, 0, Recorder());

      await manager.preLoad(AdsUnit.rewarded, 0);
      await manager.preLoad(AdsUnit.appOpen, 0);
      expect(h.rewardedRequests, 1);
      expect(h.appOpenRequests, 1);

      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
    });
  });

  group('app lifecycle', () {
    testWidgets('no full-screen ad starts while the app is in the background', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      final rec = Recorder();
      var rewardErrors = 0;
      final shows = Future.wait([
        manager.showAppOpen(ctx, 0, rec),
        manager.showInterstitial(ctx, 0, rec),
        manager.showRewarded(
          ctx,
          0,
          RewardedCallbacks(onError: (_) => rewardErrors++),
        ),
      ]);
      await tester.pump(const Duration(seconds: 3));
      await shows;
      expect(rec.errors, hasLength(2));
      expect(rewardErrors, 1);
      expect(h.totalRequests, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(2));
      expect(h.interstitialRequests, 1);
    });

    testWidgets('an ad loaded while backgrounded is kept, not shown', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      late InterstitialAdLoadCallback pending;
      h.onInterstitial = (cb) => pending = cb;
      final rec = Recorder();
      final show = manager.showInterstitial(ctx, 0, rec);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final ad = FakeInterstitial();
      pending.onAdLoaded(ad);
      await tester.pump(const Duration(seconds: 3));
      await show;
      expect(ad.shown, 0);
      expect(ad.disposed, 0);
      expect(rec.errors, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await manager.showInterstitial(ctx, 0, rec);
      expect(ad.shown, 1);
    });

    testWidgets('inactive that becomes resumed within the wait proceeds', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final rec = Recorder();
      final show = manager.showInterstitial(ctx, 0, rec);
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.interstitialRequests, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await show;
      expect(rec.errors, isEmpty);
      expect(h.interstitialRequests, 1);
    });

    testWidgets(
      'staying inactive (e.g. an SDK-restored ad on top) is refused',
      (tester) async {
        await setUpManager();
        manager.foregroundWait = const Duration(milliseconds: 500);
        final ctx = await pumpHost(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final rec = Recorder();
        final show = manager.showAppOpen(ctx, 0, rec);
        await tester.pump(const Duration(seconds: 1));
        await show;
        expect(rec.errors, hasLength(1));
        expect(rec.errors.single, contains('foreground'));
        expect(h.totalRequests, 0);
      },
    );

    testWidgets('going to the background while waiting refuses at once', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final rec = Recorder();
      final show = manager.showInterstitial(ctx, 0, rec);
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await show;
      expect(rec.errors, hasLength(1));
      expect(h.totalRequests, 0);
    });
  });

  group('cross-format', () {
    testWidgets('app open cannot overlap an interstitial', (tester) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final inter = FakeInterstitial();
      h.onInterstitial = (cb) => cb.onAdLoaded(inter);
      await manager.showInterstitial(ctx, 0, Recorder());

      final rec = Recorder();
      await manager.showAppOpen(ctx, 0, rec);
      expect(rec.errors, hasLength(1));

      inter.dismiss();
      await tester.pump();
      await manager.showAppOpen(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
      expect(h.appOpenRequests, 1);
    });
  });

  group('rewarded', () {
    testWidgets('reward granted only from the SDK callback, once', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeRewarded();
      h.onRewarded = (cb) => cb.onAdLoaded(ad);
      var rewards = 0;
      var dismissed = 0;
      var showed = 0;

      await manager.showRewarded(
        ctx,
        0,
        RewardedCallbacks(
          onShowed: () => showed++,
          onRewarded: (_) => rewards++,
          onDismissed: () => dismissed++,
        ),
      );
      expect(showed, 1);
      expect(rewards, 0);
      ad.reward();
      ad.reward();
      ad.dismiss();
      ad.dismiss();
      expect(rewards, 1);
      expect(dismissed, 1);
      expect(ad.disposed, 1);
    });

    testWidgets('dismissing without earning grants nothing', (tester) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeRewarded();
      h.onRewarded = (cb) => cb.onAdLoaded(ad);
      var rewards = 0;
      await manager.showRewarded(
        ctx,
        0,
        RewardedCallbacks(onRewarded: (_) => rewards++),
      );
      ad.dismiss();
      expect(rewards, 0);
    });

    testWidgets('load failure fires onFailedToLoad and one onError', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      h.onRewarded = (cb) =>
          cb.onAdFailedToLoad(LoadAdError(3, 'd', 'no fill', null));
      var failedToLoad = 0;
      var errors = 0;
      await manager.showRewarded(
        ctx,
        0,
        RewardedCallbacks(
          onFailedToLoad: (_) => failedToLoad++,
          onError: (_) => errors++,
        ),
      );
      expect(failedToLoad, 1);
      expect(errors, 1);
    });
  });

  group('consent (managed, default)', () {
    test('init returns without waiting for the consent form', () async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);

      expect(manager.consentInProgress, isTrue);
      expect(manager.adsAvailable.value, isFalse);
      expect(h.initCount, 0);

      h.formGate!.complete(null);
      await manager.consentReady;
      expect(manager.consentInProgress, isFalse);
      expect(manager.adsAvailable.value, isTrue);
      expect(h.order, ['consentInfoUpdate', 'consentForm', 'initialize']);
    });

    test('concurrent init calls run one flow and one SDK init', () async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      final a = manager.init(ids: testIds, status: AdsStatus.enabled);
      final b = manager.init(ids: testIds, status: AdsStatus.enabled);
      await Future.wait([a, b]);
      h.formGate!.complete(null);
      await manager.consentReady;
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      await manager.consentReady;

      expect(h.consentUpdates, 1);
      expect(h.consentForms, 1);
      expect(h.initCount, 1);
    });

    test('preLoad during the flow is deferred, then runs once', () async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);

      await manager.preLoad(AdsUnit.interstitial, 0);
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(h.interstitialRequests, 0);

      h.formGate!.complete(null);
      await manager.consentReady;
      await Future<void>.delayed(Duration.zero);
      expect(h.interstitialRequests, 1);
    });

    testWidgets('show during the flow reports an error instead of hanging', (
      tester,
    ) async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      final ctx = await pumpHost(tester);
      final rec = Recorder();
      final show = manager.showInterstitial(ctx, 0, rec);
      await tester.pump(manager.consentWait + const Duration(seconds: 1));
      await show;
      expect(rec.errors, hasLength(1));
      expect(h.interstitialRequests, 0);
      h.formGate!.complete(null);
      await manager.consentReady;
    });

    testWidgets('canRequestAds false gates every fullscreen entry point', (
      tester,
    ) async {
      await setUpManager(harness: Harness()..canRequest = false);
      final ctx = await pumpHost(tester);

      expect(manager.adsAvailable.value, isFalse);
      expect(h.initCount, 0);
      for (final unit in [
        AdsUnit.interstitial,
        AdsUnit.appOpen,
        AdsUnit.rewarded,
        AdsUnit.rewardedInt,
      ]) {
        await manager.preLoad(unit, 0);
      }
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      await manager.showAppOpen(ctx, 0, rec);
      var errors = 0;
      final cbs = RewardedCallbacks(onError: (_) => errors++);
      await manager.showRewarded(ctx, 0, cbs);
      await manager.showRewardedInterstitial(ctx, 0, cbs);

      expect(rec.errors, hasLength(2));
      expect(errors, 2);
      expect(h.totalRequests, 0);
    });

    test('update failure still honours previously stored consent', () async {
      await setUpManager(
        harness: Harness()..updateError = FormError(errorCode: 1, message: 'x'),
      );
      expect(h.order, ['consentInfoUpdate', 'initialize']);
      expect(manager.adsAvailable.value, isTrue);
    });

    test('update failure without stored consent keeps ads off', () async {
      await setUpManager(
        harness: Harness()
          ..updateError = FormError(errorCode: 1, message: 'x')
          ..canRequest = false,
      );
      expect(manager.adsAvailable.value, isFalse);
      expect(h.initCount, 0);
    });

    test('a canRequestAds error is never treated as permission', () async {
      await setUpManager(harness: Harness()..canRequestThrows = true);
      expect(manager.adsAvailable.value, isFalse);
      expect(h.initCount, 0);
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(h.interstitialRequests, 0);
    });

    test('form error does not stop the eligibility check', () async {
      await setUpManager(
        harness: Harness()..formError = FormError(errorCode: 2, message: 'f'),
      );
      expect(manager.adsAvailable.value, isTrue);
    });

    test('debug settings and age tag are forwarded (non-release)', () async {
      h = Harness();
      manager.resetForTesting(sdk: h.sdk);
      final debug = ConsentDebugSettings(
        debugGeography: DebugGeography.debugGeographyEea,
        testIdentifiers: ['ABC'],
      );
      await manager.init(
        ids: testIds,
        status: AdsStatus.enabled,
        consentDebugSettings: debug,
        tagForUnderAgeOfConsent: false,
      );
      await manager.consentReady;
      expect(h.lastParams!.consentDebugSettings, debug);
      expect(h.lastParams!.tagForUnderAgeOfConsent, isFalse);
      expect(h.resets, 0);
    });

    test('debugResetConsent only resets on explicit request', () async {
      await setUpManager();
      expect(h.resets, 0);
      await manager.debugResetConsent();
      expect(h.resets, 1);
      expect(manager.adsAvailable.value, isFalse);
    });
  });

  group('consent (external)', () {
    test('runs no UMP calls, initializes once, does not gate', () async {
      await setUpManager(
        mode: AdsConsentMode.external,
        harness: Harness()..canRequest = false,
      );
      await manager.init(
        ids: testIds,
        status: AdsStatus.enabled,
        consentMode: AdsConsentMode.external,
      );
      expect(h.consentUpdates, 0);
      expect(h.consentForms, 0);
      expect(h.initCount, 1);
      expect(manager.adsAvailable.value, isTrue);
      await manager.preLoad(AdsUnit.interstitial, 0);
      expect(h.interstitialRequests, 1);
    });
  });

  group('privacy options', () {
    test('requirement is exposed and refreshed', () async {
      await setUpManager(harness: Harness()..privacyRequired = true);
      expect(manager.privacyOptionsRequired.value, isTrue);
      h.privacyRequired = false;
      expect(await manager.isPrivacyOptionsRequired(), isFalse);
      expect(manager.privacyOptionsRequired.value, isFalse);
    });

    test('concurrent calls share one form', () async {
      await setUpManager();
      h.privacyGate = Completer<void>();
      final a = manager.showPrivacyOptionsForm();
      final b = manager.showPrivacyOptionsForm();
      await Future<void>.delayed(Duration.zero);
      h.privacyGate!.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(h.privacyForms, 1);
    });

    test('form waits for the start-up consent flow', () async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      final result = manager.showPrivacyOptionsForm();
      await Future<void>.delayed(Duration.zero);
      expect(h.privacyForms, 0);
      h.formGate!.complete(null);
      expect(await result, isTrue);
      expect(h.order, [
        'consentInfoUpdate',
        'consentForm',
        'initialize',
        'privacyForm',
      ]);
    });

    test('form error returns false', () async {
      await setUpManager(
        harness: Harness()
          ..privacyError = FormError(errorCode: 3, message: 'p'),
      );
      expect(await manager.showPrivacyOptionsForm(), isFalse);
    });

    test(
      'withdrawing consent clears cached ads and disables widgets',
      () async {
        await setUpManager();
        final cached = FakeInterstitial();
        h.onInterstitial = (cb) => cb.onAdLoaded(cached);
        await manager.preLoad(AdsUnit.interstitial, 0);
        await manager.preLoad(AdsUnit.rewarded, 0);
        expect(manager.adsAvailable.value, isTrue);

        h.canRequest = false;
        expect(await manager.showPrivacyOptionsForm(), isTrue);
        expect(manager.adsAvailable.value, isFalse);

        final before = h.totalRequests;
        await manager.preLoad(AdsUnit.interstitial, 0);
        expect(h.totalRequests, before);

        h.canRequest = true;
        await manager.showPrivacyOptionsForm();
        expect(manager.adsAvailable.value, isTrue);
        expect(h.initCount, 1);
      },
    );
  });

  test('public API: constructors from the spec compile as const', () {
    // ignore: unused_local_variable
    const a = BannerAdContainer(index: 0, type: BannerAdsType.collapsible);
    // ignore: unused_local_variable
    const b = BannerAdContainer(index: 0, type: BannerAdsType.normal);
    // ignore: unused_local_variable
    const c = BannerAdContainer(index: 0);
    // ignore: unused_local_variable
    const d = BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive);
    // ignore: unused_local_variable
    const e = BannerAdContainer(
      index: 0,
      type: BannerAdsType.fixed,
      size: BannerAdsSize.banner,
    );
    // ignore: unused_local_variable
    const f = NativeAdsContainer(index: 0, size: NativeAdsSize.small);
    expect(c.type, BannerAdsType.normal);
    expect(c.size, BannerAdsSize.banner);
    expect(a.collapsiblePlacement, BannerCollapsiblePlacement.bottom);
    expect(BannerAdsType.values, hasLength(4));
  });
}
