import 'package:admob_ads_manager/admob_ads_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'support/fakes.dart';

void main() {
  final manager = AdsManager.instance;
  late Harness h;
  late List<AdEvent> events;

  Future<void> setUpManager() async {
    h = Harness();
    manager.resetForTesting(sdk: h.sdk);
    events = [];
    manager.onAdEvent = events.add;
    await manager.init(ids: testIds, status: AdsStatus.enabled);
    await manager.consentReady;
  }

  group('preLoadWithResult', () {
    test('reports loaded, then loaded again from the cache', () async {
      await setUpManager();
      final first = await manager.preLoadWithResult(AdsUnit.appOpen, 0);
      expect(first.outcome, AdLoadOutcome.loaded);
      expect(h.appOpenRequests, 1);
      final second = await manager.preLoadWithResult(AdsUnit.appOpen, 0);
      expect(second.isLoaded, isTrue);
      expect(h.appOpenRequests, 1);
    });

    test('reports the SDK error code on a failed load', () async {
      await setUpManager();
      h.onInterstitial = (cb) =>
          cb.onAdFailedToLoad(LoadAdError(3, 'domain', 'no fill', null));
      final result = await manager.preLoadWithResult(AdsUnit.interstitial, 0);
      expect(result.outcome, AdLoadOutcome.failed);
      expect(result.errorCode, 3);
      // preLoad itself still never throws.
      await manager.preLoad(AdsUnit.interstitial, 0);
    });

    test('is deferred while consent is not granted', () async {
      h = Harness()..canRequest = false;
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      await manager.consentReady;
      final result = await manager.preLoadWithResult(AdsUnit.appOpen, 0);
      expect(result.outcome, AdLoadOutcome.deferred);
      expect(h.appOpenRequests, 0);
    });

    test('is unavailable for banners and when ads are disabled', () async {
      await setUpManager();
      expect(
        (await manager.preLoadWithResult(AdsUnit.banner, 0)).outcome,
        AdLoadOutcome.unavailable,
      );
    });
  });

  group('events', () {
    test('request, loaded and failed carry the unit and error code', () async {
      await setUpManager();
      await manager.preLoadWithResult(AdsUnit.appOpen, 0);
      h.onInterstitial = (cb) =>
          cb.onAdFailedToLoad(LoadAdError(2, 'domain', 'network', null));
      await manager.preLoadWithResult(AdsUnit.interstitial, 0);
      expect(events.map((e) => '${e.type.name}:${e.unit.name}'), [
        'request:appOpen',
        'loaded:appOpen',
        'request:interstitial',
        'failed:interstitial',
      ]);
      expect(events.last.errorCode, 2);
    });

    test('a throwing handler never breaks loading', () async {
      await setUpManager();
      manager.onAdEvent = (_) => throw StateError('boom');
      final result = await manager.preLoadWithResult(AdsUnit.appOpen, 0);
      expect(result.isLoaded, isTrue);
    });
  });

  group('banner auto retry', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BannerAdContainer(index: 0)),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('is off by default', (tester) async {
      await setUpManager();
      await pump(tester);
      h.banners.single.fireFailed();
      await tester.pump(const Duration(minutes: 1));
      expect(h.banners, hasLength(1));
    });

    testWidgets('retries after 2 s, 4 s, 8 s and then stops', (tester) async {
      await setUpManager();
      manager.autoRetryBackoff = const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ];
      await pump(tester);
      h.banners.last.fireFailed();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(h.banners, hasLength(2));
      h.banners.last.fireFailed();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(h.banners, hasLength(3));
      h.banners.last.fireFailed();
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(h.banners, hasLength(4));
      h.banners.last.fireFailed();
      await tester.pump(const Duration(minutes: 5));
      expect(h.banners, hasLength(4)); // capped
      // An explicit retry starts the schedule again.
      manager.retryFailedAds();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(5));
    });
  });
}
