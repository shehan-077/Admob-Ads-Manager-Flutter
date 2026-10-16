import 'dart:async';

import 'package:admob_ads_manager/admob_ads_manager.dart';
import 'package:admob_ads_manager/src/banner_config.dart';
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
    Harness? harness,
  }) async {
    h = harness ?? Harness();
    manager.resetForTesting(sdk: h.sdk);
    await manager.init(ids: testIds, status: status);
    await manager.consentReady;
  }

  Future<void> pumpBanner(
    WidgetTester tester,
    BannerAdContainer banner, {
    double width = 400,
    double height = 600,
    Size screen = const Size(800, 600),
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screen, viewInsets: viewInsets),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, height: height, child: banner),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('helpers', () {
    test('size enum maps to the SDK sizes', () {
      expect(BannerAdsSize.banner.adSize, AdSize.banner);
      expect(BannerAdsSize.largeBanner.adSize, AdSize.largeBanner);
      expect(BannerAdsSize.mediumRectangle.adSize, AdSize.mediumRectangle);
      expect(BannerAdsSize.fullBanner.adSize, AdSize.fullBanner);
      expect(BannerAdsSize.leaderboard.adSize, AdSize.leaderboard);
      expect(BannerAdsSize.fullBanner.tabletOnly, isTrue);
      expect(BannerAdsSize.banner.tabletOnly, isFalse);
    });

    test(
      'collapsible request adds the extra and preserves everything else',
      () {
        const base = AdRequest(
          keywords: ['a'],
          contentUrl: 'https://example.com',
          nonPersonalizedAds: true,
          extras: {'x': 'y'},
        );
        final bottom = buildBannerRequest(
          base,
          BannerAdsType.collapsible,
          BannerCollapsiblePlacement.bottom,
        );
        expect(bottom.extras, {'x': 'y', 'collapsible': 'bottom'});
        expect(bottom.keywords, ['a']);
        expect(bottom.contentUrl, 'https://example.com');
        expect(bottom.nonPersonalizedAds, isTrue);
        expect(base.extras, {'x': 'y'});

        final top = buildBannerRequest(
          null,
          BannerAdsType.collapsible,
          BannerCollapsiblePlacement.top,
        );
        expect(top.extras, {'collapsible': 'top'});
      },
    );

    test('other banner types do not add collapsible extras', () {
      for (final type in [
        BannerAdsType.normal,
        BannerAdsType.inlineAdaptive,
        BannerAdsType.fixed,
      ]) {
        final r = buildBannerRequest(
          null,
          type,
          BannerCollapsiblePlacement.bottom,
        );
        expect(r.extras, isNull);
      }
    });

    test('resolveBannerWidth accounts for constraints and safe areas', () {
      expect(
        resolveBannerWidth(
          maxWidth: 800,
          screenWidth: 800,
          horizontalInset: 88,
        ),
        712,
      );
      expect(
        resolveBannerWidth(
          maxWidth: 368,
          screenWidth: 400,
          horizontalInset: 44,
        ),
        368,
      );
      expect(
        resolveBannerWidth(
          maxWidth: double.infinity,
          screenWidth: 400,
          horizontalInset: 0,
        ),
        400,
      );
      expect(
        resolveBannerWidth(maxWidth: 0, screenWidth: 400, horizontalInset: 0),
        0,
      );
    });

    test('fixedBannerFits never lets an ad overflow', () {
      expect(
        fixedBannerFits(AdSize.banner, const BoxConstraints(maxWidth: 320)),
        isTrue,
      );
      expect(
        fixedBannerFits(AdSize.banner, const BoxConstraints(maxWidth: 319)),
        isFalse,
      );
      expect(
        fixedBannerFits(
          AdSize.mediumRectangle,
          const BoxConstraints(maxWidth: 400, maxHeight: 200),
        ),
        isFalse,
      );
    });
  });

  group('normal banner', () {
    testWidgets('anchored adaptive size from actual constraints', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 1));
      expect(h.lastAnchoredWidth, 400);
      expect(h.lastOrientation, Orientation.landscape);
      expect(h.banners, hasLength(1));
      expect(h.banners.single.adUnitId, 'ban1');
      expect(h.banners.single.size.width, 400);
      expect(h.banners.single.request.extras, isNull);

      h.banners.single.fireLoaded();
      await tester.pump();
      final box = tester.getSize(
        find.byKey(ValueKey('ad-${h.banners.single.hashCode}')),
      );
      expect(box, const Size(400, 60));
    });

    testWidgets('keyboard and rebuilds do not reload; width change does', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, hasLength(1));

      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0),
        viewInsets: const EdgeInsets.only(bottom: 300),
      );
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, hasLength(1));

      await pumpBanner(tester, const BannerAdContainer(index: 0), width: 500);
      expect(h.banners, hasLength(2));
      expect(h.banners.first.disposed, 0);
      h.banners.first.fireLoaded();
      await tester.pump();
      expect(h.banners.first.disposed, 1);
      expect(
        find.byKey(ValueKey('ad-${h.banners.first.hashCode}')),
        findsNothing,
      );
    });

    testWidgets('index and type changes replace the ad exactly once', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final first = h.banners.single..fireLoaded();
      await tester.pump();

      await pumpBanner(tester, const BannerAdContainer(index: 1));
      expect(h.banners, hasLength(2));
      expect(first.disposed, 1);
      expect(h.banners.last.adUnitId, 'ban1');

      await pumpBanner(
        tester,
        const BannerAdContainer(index: 1, type: BannerAdsType.fixed),
      );
      expect(h.banners, hasLength(3));
      first.fireLoaded();
      await tester.pump();
      expect(first.disposed, 1);
    });

    testWidgets('no fill: ad disposed once, no automatic retry', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final banner = h.banners.single..fireFailed();
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(banner.disposed, 1);
      expect(h.banners, hasLength(1));
    });

    testWidgets('disposed while loading cleans up the late ad', (tester) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final banner = h.banners.single;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      banner.fireLoaded();
      await tester.pump();
      expect(banner.disposed, 1);
    });

    testWidgets(
      'widgets created before readiness load when ads become eligible',
      (tester) async {
        h = Harness()..formGate = Completer<FormError?>();
        manager.resetForTesting(sdk: h.sdk);
        await manager.init(ids: testIds, status: AdsStatus.enabled);

        await pumpBanner(tester, const BannerAdContainer(index: 0));
        expect(h.banners, isEmpty);

        h.formGate!.complete(null);
        await manager.consentReady;
        await tester.pump();
        await tester.pump();
        expect(h.banners, hasLength(1));
      },
    );

    testWidgets('consent withdrawal removes the ad; regaining reloads', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final banner = h.banners.single..fireLoaded();
      await tester.pump();

      h.canRequest = false;
      await manager.showPrivacyOptionsForm();
      await tester.pump();
      await tester.pump();
      expect(banner.disposed, 1);
      expect(find.byKey(ValueKey('ad-${banner.hashCode}')), findsNothing);

      h.canRequest = true;
      await manager.showPrivacyOptionsForm();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(2));
    });

    testWidgets('ineligible consent never creates an ad', (tester) async {
      await setUpManager(harness: Harness()..canRequest = false);
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, isEmpty);
    });

    testWidgets('ads disabled renders nothing and requests nothing', (
      tester,
    ) async {
      await setUpManager(status: AdsStatus.disabled);
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, isEmpty);
    });

    testWidgets('before init() nothing is created and nothing throws', (
      tester,
    ) async {
      h = Harness();
      manager.resetForTesting(sdk: h.sdk);
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the official test unit in testing mode', (tester) async {
      await setUpManager(status: AdsStatus.testing);
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(
        h.banners.single.adUnitId,
        'ca-app-pub-3940256099942544/6300978111',
      );
    });
  });

  group('collapsible banner', () {
    testWidgets('requests with bottom placement by default', (tester) async {
      await setUpManager(status: AdsStatus.testing);
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.collapsible),
      );
      final banner = h.banners.single;
      expect(banner.request.extras, {'collapsible': 'bottom'});
      expect(banner.adUnitId, 'ca-app-pub-3940256099942544/2014213617');
      expect(banner.size.height, 60);
    });

    testWidgets('top placement keeps configured extras; fallback is success', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(
          index: 0,
          type: BannerAdsType.collapsible,
          collapsiblePlacement: BannerCollapsiblePlacement.top,
          request: AdRequest(extras: {'k': 'v'}),
        ),
      );
      final banner = h.banners.single;
      expect(banner.request.extras, {'k': 'v', 'collapsible': 'top'});
      banner.fireLoaded();
      await tester.pump();
      expect(find.byKey(ValueKey('ad-${banner.hashCode}')), findsOneWidget);
      await tester.pump(const Duration(minutes: 10));
      expect(h.banners, hasLength(1));
    });

    testWidgets('placement change reloads', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.collapsible),
      );
      await pumpBanner(
        tester,
        const BannerAdContainer(
          index: 0,
          type: BannerAdsType.collapsible,
          collapsiblePlacement: BannerCollapsiblePlacement.top,
        ),
      );
      expect(h.banners, hasLength(2));
      expect(h.banners.last.request.extras, {'collapsible': 'top'});
    });
  });

  group('inline adaptive banner', () {
    testWidgets('uses the platform size after load', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive),
      );
      final banner = h.banners.single;
      expect(banner.size, isA<InlineAdaptiveSize>());
      expect(banner.size.width, 400);
      expect(banner.size.height, 0);
      banner.platformSize = AdSize(width: 400, height: 250);
      banner.fireLoaded();
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSize(find.byKey(ValueKey('ad-${banner.hashCode}'))),
        const Size(400, 250),
      );
    });

    testWidgets('maxHeight is passed to the SDK size', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(
          index: 0,
          type: BannerAdsType.inlineAdaptive,
          maxHeight: 200,
        ),
      );
      expect((h.banners.single.size as InlineAdaptiveSize).maxHeight, 200);
    });

    testWidgets('size resolved after disposal is discarded', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive),
      );
      final banner = h.banners.single..platformGate = Completer<AdSize?>();
      banner.fireLoaded();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      banner.platformGate!.complete(AdSize(width: 400, height: 250));
      await tester.pump();
      expect(banner.disposed, 1);
    });

    testWidgets('size resolved after replacement is discarded', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive),
      );
      final old = h.banners.single..platformGate = Completer<AdSize?>();
      old.fireLoaded();

      await pumpBanner(
        tester,
        const BannerAdContainer(index: 1, type: BannerAdsType.inlineAdaptive),
      );
      expect(h.banners, hasLength(2));
      old.platformGate!.complete(AdSize(width: 400, height: 250));
      await tester.pump();
      await tester.pump();
      expect(old.disposed, 1);
      expect(find.byKey(ValueKey('ad-${old.hashCode}')), findsNothing);
    });

    testWidgets('size resolved after orientation change is discarded', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive),
      );
      final old = h.banners.single..platformGate = Completer<AdSize?>();
      old.fireLoaded();

      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive),
        screen: const Size(400, 800),
      );
      expect(h.banners, hasLength(2));
      old.platformGate!.complete(AdSize(width: 400, height: 250));
      await tester.pump();
      await tester.pump();
      expect(old.disposed, 1);
      expect(find.byKey(ValueKey('ad-${old.hashCode}')), findsNothing);
    });

    testWidgets('missing platform size is a failure, ad disposed', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.inlineAdaptive),
      );
      final banner = h.banners.single..platformSize = null;
      banner.fireLoaded();
      await tester.pump();
      await tester.pump();
      expect(banner.disposed, 1);
    });
  });

  group('fixed banner', () {
    testWidgets('loads the mapped size when it fits', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(
          index: 0,
          type: BannerAdsType.fixed,
          size: BannerAdsSize.mediumRectangle,
        ),
      );
      expect(h.banners.single.size, AdSize.mediumRectangle);
      h.banners.single.fireLoaded();
      await tester.pump();
      expect(
        tester.getSize(find.byKey(ValueKey('ad-${h.banners.single.hashCode}'))),
        const Size(300, 250),
      );
    });

    testWidgets('default fixed size is banner', (tester) async {
      await setUpManager();
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.fixed),
      );
      expect(h.banners.single.size, AdSize.banner);
    });

    testWidgets('insufficient space: nothing loaded, diagnostic logged', (
      tester,
    ) async {
      await setUpManager();
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');

      await pumpBanner(
        tester,
        const BannerAdContainer(
          index: 0,
          type: BannerAdsType.fixed,
          size: BannerAdsSize.leaderboard,
        ),
        width: 400,
      );
      expect(h.banners, isEmpty);
      expect(logs.where((l) => l.contains('does not fit')), hasLength(1));
      expect(logs.join(), contains('tablets'));
      await tester.pump();
      expect(logs.where((l) => l.contains('does not fit')), hasLength(1));

      await pumpBanner(
        tester,
        const BannerAdContainer(
          index: 0,
          type: BannerAdsType.fixed,
          size: BannerAdsSize.leaderboard,
        ),
        width: 760,
        screen: const Size(900, 600),
      );
      debugPrint = original;
      expect(h.banners, hasLength(1));
    });
  });

  group('native ads', () {
    testWidgets('existing API: loads, replaces on change, cleans up', (
      tester,
    ) async {
      await setUpManager(status: AdsStatus.testing);
      Future<void> pump(Widget w) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
        await tester.pump();
      }

      await pump(const NativeAdsContainer(index: 0, size: NativeAdsSize.small));
      expect(h.natives, hasLength(1));
      expect(
        h.natives.single.adUnitId,
        'ca-app-pub-3940256099942544/2247696110',
      );
      expect(h.natives.single.style.templateType, TemplateType.small);
      final first = h.natives.single..fireLoaded();
      await tester.pump();
      expect(find.byKey(ValueKey('ad-${first.hashCode}')), findsOneWidget);

      await pump(
        const NativeAdsContainer(index: 0, size: NativeAdsSize.medium),
      );
      await tester.pump();
      expect(h.natives, hasLength(2));
      expect(first.disposed, 1);
      expect(h.natives.last.style.templateType, TemplateType.medium);

      first.fireLoaded();
      await tester.pump();
      expect(first.disposed, 1);
      expect(find.byKey(ValueKey('ad-${first.hashCode}')), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(h.natives.last.disposed, 0);
      h.natives.last.fireLoaded();
      await tester.pump();
      expect(h.natives.last.disposed, 1);
    });

    testWidgets('waits for eligibility and reacts to withdrawal', (
      tester,
    ) async {
      h = Harness()..formGate = Completer<FormError?>();
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      await tester.pumpWidget(
        const MaterialApp(
          home: NativeAdsContainer(index: 1, size: NativeAdsSize.small),
        ),
      );
      expect(h.natives, isEmpty);

      h.formGate!.complete(null);
      await manager.consentReady;
      await tester.pump();
      expect(h.natives, hasLength(1));
      expect(h.natives.single.adUnitId, 'nat1');
      final ad = h.natives.single..fireLoaded();
      await tester.pump();

      h.canRequest = false;
      await manager.showPrivacyOptionsForm();
      await tester.pump();
      await tester.pump();
      expect(ad.disposed, 1);
    });

    testWidgets('no fill disposes once and does not retry', (tester) async {
      await setUpManager();
      await tester.pumpWidget(
        const MaterialApp(
          home: NativeAdsContainer(index: 0, size: NativeAdsSize.small),
        ),
      );
      final ad = h.natives.single..fireFailed();
      await tester.pump(const Duration(minutes: 5));
      expect(ad.disposed, 1);
      expect(h.natives, hasLength(1));
    });

    testWidgets('invalid configuration does not throw', (tester) async {
      await setUpManager();
      await tester.pumpWidget(
        const MaterialApp(
          home: NativeAdsContainer(index: -1, size: NativeAdsSize.small),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(h.natives, isEmpty);
    });
  });

  group('changes while loading', () {
    testWidgets('banner index change while the size is resolving', (
      tester,
    ) async {
      await setUpManager();
      h.anchoredGate = Completer<void>();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, isEmpty);
      expect(h.anchoredCalls, 1);

      await pumpBanner(tester, const BannerAdContainer(index: 1));
      expect(h.anchoredCalls, 2);

      h.anchoredGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
      expect(h.banners.single.adUnitId, 'ban1');
    });

    testWidgets('banner type change while the ad is loading', (tester) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final normal = h.banners.single;
      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0, type: BannerAdsType.collapsible),
      );
      normal.fireLoaded();
      await tester.pump();
      expect(normal.disposed, 1);
      expect(h.banners, hasLength(2));
      h.banners.last.fireLoaded();
      await tester.pump();
      expect(
        find.byKey(ValueKey('ad-${h.banners.last.hashCode}')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('ad-${normal.hashCode}')), findsNothing);
    });

    testWidgets('orientation change replaces a normal banner', (tester) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.lastOrientation, Orientation.landscape);
      final first = h.banners.single..fireLoaded();
      await tester.pump();

      await pumpBanner(
        tester,
        const BannerAdContainer(index: 0),
        screen: const Size(400, 800),
      );
      expect(h.lastOrientation, Orientation.portrait);
      expect(h.banners, hasLength(2));
      expect(first.disposed, 1);
    });

    testWidgets('native index change while loading', (tester) async {
      await setUpManager();
      Future<void> pump(Widget w) async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
        await tester.pump();
      }

      await pump(const NativeAdsContainer(index: 0, size: NativeAdsSize.small));
      final old = h.natives.single;
      await pump(const NativeAdsContainer(index: 1, size: NativeAdsSize.small));
      expect(h.natives, hasLength(2));
      old.fireLoaded();
      await tester.pump();
      expect(old.disposed, 1);
      expect(find.byKey(ValueKey('ad-${old.hashCode}')), findsNothing);
      h.natives.last.fireLoaded();
      await tester.pump();
      expect(
        find.byKey(ValueKey('ad-${h.natives.last.hashCode}')),
        findsOneWidget,
      );
      expect(h.natives.last.adUnitId, 'nat1');
    });

    testWidgets('native replaced twice keeps only the latest ad', (
      tester,
    ) async {
      await setUpManager();
      Future<void> pump(NativeAdsSize size) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: NativeAdsContainer(index: 0, size: size)),
          ),
        );
        await tester.pump();
      }

      await pump(NativeAdsSize.small);
      await pump(NativeAdsSize.medium);
      await pump(NativeAdsSize.small);
      expect(h.natives, hasLength(3));
      for (final ad in h.natives) {
        ad.fireLoaded();
      }
      await tester.pump();
      expect(h.natives[0].disposed, 1);
      expect(h.natives[1].disposed, 1);
      expect(h.natives[2].disposed, 0);
    });
  });

  group('retry', () {
    testWidgets('a failed banner is retried only on request', (tester) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final failed = h.banners.single..fireFailed();
      await tester.pump();
      await tester.pump(const Duration(minutes: 10));
      expect(h.banners, hasLength(1));

      manager.retryFailedAds();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(2));
      expect(failed.disposed, 1);
      h.banners.last.fireLoaded();
      await tester.pump();
      expect(
        find.byKey(ValueKey('ad-${h.banners.last.hashCode}')),
        findsOneWidget,
      );
    });

    testWidgets('retry is ignored while loading and when an ad is shown', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      manager.retryFailedAds();
      await tester.pump();
      expect(h.banners, hasLength(1));

      h.banners.single.fireLoaded();
      await tester.pump();
      manager.retryFailedAds();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
      expect(h.banners.single.disposed, 0);
    });

    testWidgets('retry is filtered by unit and index', (tester) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 1));
      h.banners.single.fireFailed();
      await tester.pump();

      manager.retryFailedAds(unit: AdsUnit.native);
      manager.retryFailedAds(index: 0);
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));

      manager.retryFailedAds(unit: AdsUnit.banner, index: 1);
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(2));
    });

    testWidgets('retry is ignored when ads are not available', (tester) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      h.banners.single.fireFailed();
      await tester.pump();

      h.canRequest = false;
      await manager.refreshAvailability();
      manager.retryFailedAds();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
    });

    testWidgets('retry works after the size lookup failed', (tester) async {
      await setUpManager();
      h.anchoredNull = true;
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      expect(h.banners, isEmpty);

      h.anchoredNull = false;
      manager.retryFailedAds();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(1));
    });

    testWidgets('a stale failure after replacement does not mark a retry', (
      tester,
    ) async {
      await setUpManager();
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      final old = h.banners.single;
      await pumpBanner(tester, const BannerAdContainer(index: 1));
      old.fireFailed();
      await tester.pump();
      manager.retryFailedAds();
      await tester.pump();
      await tester.pump();
      expect(h.banners, hasLength(2));
      expect(old.disposed, 1);
    });

    testWidgets('a failed native ad is retried on request', (tester) async {
      await setUpManager();
      await tester.pumpWidget(
        const MaterialApp(
          home: NativeAdsContainer(index: 0, size: NativeAdsSize.small),
        ),
      );
      final failed = h.natives.single..fireFailed();
      await tester.pump(const Duration(minutes: 10));
      expect(h.natives, hasLength(1));

      manager.retryFailedAds(unit: AdsUnit.native);
      await tester.pump();
      expect(h.natives, hasLength(2));
      expect(failed.disposed, 1);

      manager.retryFailedAds();
      await tester.pump();
      expect(h.natives, hasLength(2));
    });

    testWidgets('retry does nothing when ads are disabled', (tester) async {
      await setUpManager(status: AdsStatus.disabled);
      await pumpBanner(tester, const BannerAdContainer(index: 0));
      manager.retryFailedAds();
      await tester.pump();
      expect(h.banners, isEmpty);
    });
  });

  group('native sizing', () {
    test('defaults and clamping follow the documented template range', () {
      expect(resolveNativeHeight(NativeAdsSize.small, null), 120);
      expect(resolveNativeHeight(NativeAdsSize.medium, null), 320);
      expect(
        resolveNativeHeight(NativeAdsSize.medium, null, availableWidth: 392),
        closeTo(360.6, 0.1),
      );
      expect(
        resolveNativeHeight(NativeAdsSize.medium, null, availableWidth: 300),
        320,
      );
      expect(
        resolveNativeHeight(NativeAdsSize.medium, null, availableWidth: 900),
        400,
      );
      expect(
        resolveNativeHeight(NativeAdsSize.small, null, availableWidth: 900),
        120,
      );
      expect(resolveNativeHeight(NativeAdsSize.small, 10), 90);
      expect(resolveNativeHeight(NativeAdsSize.small, 500), 200);
      expect(resolveNativeHeight(NativeAdsSize.medium, 100), 320);
      expect(resolveNativeHeight(NativeAdsSize.medium, 380), 380);
      expect(resolveNativeHeight(NativeAdsSize.medium, double.nan), 320);
    });

    testWidgets('optional height and maxWidth are applied', (tester) async {
      await setUpManager();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeAdsContainer(
              index: 0,
              size: NativeAdsSize.medium,
              height: 380,
              maxWidth: 360,
            ),
          ),
        ),
      );
      final ad = h.natives.single..fireLoaded();
      await tester.pump();
      expect(
        tester.getSize(find.byKey(ValueKey('ad-${ad.hashCode}'))),
        const Size(360, 380),
      );
    });

    testWidgets('default constructor keeps the existing sizes', (tester) async {
      await setUpManager();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeAdsContainer(index: 0, size: NativeAdsSize.small),
          ),
        ),
      );
      final ad = h.natives.single..fireLoaded();
      await tester.pump();
      expect(
        tester.getSize(find.byKey(ValueKey('ad-${ad.hashCode}'))).height,
        120,
      );
    });
  });

  group('placement in app bars', () {
    testWidgets('banner in bottomNavigationBar hugs the bottom edge', (
      tester,
    ) async {
      await setUpManager();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(),
            bottomNavigationBar: BannerAdContainer(index: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final banner = h.banners.single..fireLoaded();
      await tester.pump();
      final rect = tester.getRect(
        find.byKey(ValueKey('ad-${banner.hashCode}')),
      );
      expect(rect.bottom, 800);
      expect(rect.height, 60);
    });

    testWidgets('banner in appBar-less top column hugs the top', (
      tester,
    ) async {
      await setUpManager();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BannerAdContainer(
                  index: 0,
                  type: BannerAdsType.collapsible,
                  collapsiblePlacement: BannerCollapsiblePlacement.top,
                ),
                Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final banner = h.banners.single..fireLoaded();
      await tester.pump();
      final rect = tester.getRect(
        find.byKey(ValueKey('ad-${banner.hashCode}')),
      );
      expect(rect.top, 0);
    });

    testWidgets('native ad does not expand to fill a bounded parent', (
      tester,
    ) async {
      await setUpManager();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                NativeAdsContainer(index: 0, size: NativeAdsSize.small),
                Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      );
      final ad = h.natives.single..fireLoaded();
      await tester.pump();
      final rect = tester.getRect(find.byKey(ValueKey('ad-${ad.hashCode}')));
      expect(rect.top, 0);
      expect(rect.height, 120);
    });
  });

  group('iOS small template media size', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('effectiveNativeSize switches small to medium only on narrow iOS', () {
      NativeAdsSize pick(
        double width, {
        TargetPlatform platform = TargetPlatform.iOS,
        bool fallback = true,
        NativeAdsSize size = NativeAdsSize.small,
      }) => effectiveNativeSize(
        size,
        availableWidth: width,
        iosSmallMediaFallback: fallback,
        platform: platform,
      );

      expect(pick(393), NativeAdsSize.medium);
      expect(pick(479.9), NativeAdsSize.medium);
      expect(pick(480), NativeAdsSize.small); // 25% of 480 = 120 points
      expect(pick(852), NativeAdsSize.small);
      expect(pick(393, platform: TargetPlatform.android), NativeAdsSize.small);
      expect(pick(393, fallback: false), NativeAdsSize.small);
      expect(pick(393, size: NativeAdsSize.medium), NativeAdsSize.medium);
    });

    Future<void> pumpNative(
      WidgetTester tester,
      double width, {
      bool fallback = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: NativeAdsContainer(
                  index: 0,
                  size: NativeAdsSize.small,
                  iosSmallMediaFallback: fallback,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('iPhone width requests the medium template', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await setUpManager();
      await pumpNative(tester, 393);
      expect(h.natives.single.style.templateType, TemplateType.medium);
      final ad = h.natives.single..fireLoaded();
      await tester.pump();
      final height = tester
          .getSize(find.byKey(ValueKey('ad-${ad.hashCode}')))
          .height;
      expect(height, greaterThanOrEqualTo(320));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('wide iOS and any Android keep the small template', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await setUpManager();
      await pumpNative(tester, 600);
      expect(h.natives.single.style.templateType, TemplateType.small);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(const SizedBox());
      await setUpManager();
      await pumpNative(tester, 393);
      expect(h.natives.single.style.templateType, TemplateType.small);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('opting out keeps the small template on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await setUpManager();
      await pumpNative(tester, 393, fallback: false);
      expect(h.natives.single.style.templateType, TemplateType.small);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a width change that crosses the limit swaps the template', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await setUpManager();
      await pumpNative(tester, 393);
      final narrow = h.natives.single..fireLoaded();
      await tester.pump();

      await pumpNative(tester, 600);
      expect(h.natives, hasLength(2));
      expect(h.natives.last.style.templateType, TemplateType.small);
      expect(narrow.disposed, 1);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
