import 'dart:async';

import 'package:admob_ads_manager/admob_ads_manager.dart';
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

  group('readiness semantics', () {
    test(
      'whenReady is true when consent allows and the SDK initialized',
      () async {
        await setUpManager();
        expect(await manager.whenReady(), isTrue);
        expect(manager.isSdkInitialized, isTrue);
        expect(manager.adsAvailable.value, isTrue);
      },
    );

    test(
      'consentReady completes while ads stay unavailable (declined)',
      () async {
        await setUpManager(harness: Harness()..canRequest = false);
        await manager.consentReady;
        expect(manager.consentInProgress, isFalse);
        expect(manager.isSdkInitialized, isFalse);
        expect(await manager.whenReady(), isFalse);
      },
    );

    test(
      'whenReady does not hang when ads are disabled or init not called',
      () async {
        h = Harness();
        manager.resetForTesting(sdk: h.sdk);
        expect(
          await manager.whenReady().timeout(const Duration(seconds: 1)),
          isFalse,
        );
        await setUpManager(status: AdsStatus.disabled);
        expect(
          await manager.whenReady().timeout(const Duration(seconds: 1)),
          isFalse,
        );
        expect(await manager.refreshAvailability(), isFalse);
      },
    );

    test(
      'whenReady waits for the consent form, then reports availability',
      () async {
        h = Harness()..formGate = Completer<FormError?>();
        manager.resetForTesting(sdk: h.sdk);
        await manager.init(ids: testIds, status: AdsStatus.enabled);
        var done = false;
        final ready = manager.whenReady().then((v) {
          done = true;
          return v;
        });
        await Future<void>.delayed(Duration.zero);
        expect(done, isFalse);
        h.formGate!.complete(null);
        expect(await ready, isTrue);
      },
    );

    test(
      'external mode: init awaits the SDK, whenReady is immediate',
      () async {
        await setUpManager(mode: AdsConsentMode.external);
        expect(manager.isSdkInitialized, isTrue);
        expect(await manager.whenReady(), isTrue);
      },
    );
  });

  group('consent update failure and recovery', () {
    test('refreshAvailability repeats a failed consent update once', () async {
      h = Harness()
        ..updateError = FormError(errorCode: 1, message: 'offline')
        ..canRequest = false;
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      await manager.consentReady;
      expect(await manager.whenReady(), isFalse);
      expect(h.consentUpdates, 1);

      h.updateError = null;
      h.canRequest = true;
      final results = await Future.wait([
        manager.refreshAvailability(),
        manager.refreshAvailability(),
      ]);
      expect(results, [true, true]);
      expect(h.consentUpdates, 2);
      expect(h.consentForms, 1);
      expect(h.initCount, 1);
      expect(manager.adsAvailable.value, isTrue);

      await manager.refreshAvailability();
      expect(h.consentUpdates, 2);
    });

    test('a failed update with stored consent stays available', () async {
      h = Harness()..updateError = FormError(errorCode: 1, message: 'offline');
      manager.resetForTesting(sdk: h.sdk);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      expect(await manager.whenReady(), isTrue);
    });
  });

  group('initialization failure and recovery', () {
    test(
      'managed: failure completes readiness, refreshAvailability recovers',
      () async {
        await setUpManager(harness: Harness()..initFailures = 1);
        expect(manager.consentInProgress, isFalse);
        expect(await manager.whenReady(), isFalse);
        expect(manager.isSdkInitialized, isFalse);

        await manager.preLoad(AdsUnit.interstitial, 0);
        expect(h.initCount, 2);

        expect(await manager.refreshAvailability(), isTrue);
        expect(manager.isSdkInitialized, isTrue);
        expect(await manager.whenReady(), isTrue);
      },
    );

    test('managed: refreshAvailability retries after a failed init', () async {
      await setUpManager(harness: Harness()..initFailures = 2);
      expect(manager.adsAvailable.value, isFalse);
      expect(await manager.refreshAvailability(), isFalse);
      expect(await manager.refreshAvailability(), isTrue);
      expect(h.initCount, 3);
    });

    test('external: init throws, a second init recovers', () async {
      h = Harness()..initFailures = 1;
      manager.resetForTesting(sdk: h.sdk);
      await expectLater(
        manager.init(
          ids: testIds,
          status: AdsStatus.enabled,
          consentMode: AdsConsentMode.external,
        ),
        throwsStateError,
      );
      expect(manager.adsAvailable.value, isFalse);
      await manager.init(
        ids: testIds,
        status: AdsStatus.enabled,
        consentMode: AdsConsentMode.external,
      );
      expect(manager.adsAvailable.value, isTrue);
    });

    test('a hanging SDK init times out instead of hanging readiness', () async {
      h = Harness()..initGate = Completer<void>();
      manager.resetForTesting(sdk: h.sdk);
      manager.sdkInitTimeout = const Duration(milliseconds: 50);
      await manager.init(ids: testIds, status: AdsStatus.enabled);
      expect(await manager.whenReady(), isFalse);

      h.initGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(await manager.refreshAvailability(), isTrue);
      expect(h.initCount, 1);
    });

    test(
      'preload failing on init error is reported without throwing',
      () async {
        await setUpManager(mode: AdsConsentMode.external, harness: Harness());
        h.initFailures = 0;
        manager.resetForTesting(sdk: h.sdk);
        await manager.init(
          ids: testIds,
          status: AdsStatus.enabled,
          consentMode: AdsConsentMode.external,
        );
        h.initFailures = 1;
        await manager.preLoad(AdsUnit.interstitial, 0);
      },
    );
  });

  group('consent changes while loads are pending', () {
    test(
      'a pending preload that completes after withdrawal is disposed',
      () async {
        await setUpManager();
        late InterstitialAdLoadCallback pending;
        h.onInterstitial = (cb) => pending = cb;
        final load = manager.preLoad(AdsUnit.interstitial, 0);
        await Future<void>.delayed(Duration.zero);

        h.canRequest = false;
        await manager.showPrivacyOptionsForm();
        final late = FakeInterstitial();
        pending.onAdLoaded(late);
        await load;
        expect(late.disposed, 1);

        h.canRequest = true;
        await manager.showPrivacyOptionsForm();
        h.onInterstitial = (cb) => cb.onAdLoaded(FakeInterstitial());
        await manager.preLoad(AdsUnit.interstitial, 0);
        expect(h.interstitialRequests, 2);
      },
    );

    testWidgets(
      'a show waiting on a load ends with one error after withdrawal',
      (tester) async {
        await setUpManager();
        final ctx = await pumpHost(tester);
        late InterstitialAdLoadCallback pending;
        h.onInterstitial = (cb) => pending = cb;
        final rec = Recorder();
        final show = manager.showInterstitial(ctx, 0, rec);
        await tester.pump();

        h.canRequest = false;
        await manager.showPrivacyOptionsForm();
        final late = FakeInterstitial();
        pending.onAdLoaded(late);
        await show;
        await tester.pump();

        expect(late.disposed, 1);
        expect(late.shown, 0);
        expect(rec.errors, hasLength(1));
        expect(rec.success, 0);
      },
    );

    test('concurrent eligibility refreshes: the latest one wins', () async {
      await setUpManager();
      h.canRequest = false;
      final a = manager.showPrivacyOptionsForm();
      h.canRequest = true;
      final b = manager.refreshAvailability();
      await Future.wait([a, b]);
      expect(manager.adsAvailable.value, isTrue);
    });
  });

  group('rewards', () {
    Future<(FakeRewarded, List<String>)> showRewarded(
      WidgetTester tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeRewarded();
      h.onRewarded = (cb) => cb.onAdLoaded(ad);
      final events = <String>[];
      await manager.showRewarded(
        ctx,
        0,
        RewardedCallbacks(
          onShowed: () => events.add('showed'),
          onRewarded: (r) => events.add('rewarded:${r.amount}'),
          onDismissed: () => events.add('dismissed'),
          onFailedToShow: (_) => events.add('failedToShow'),
        ),
      );
      return (ad, events);
    }

    testWidgets('reward before dismissal', (tester) async {
      final (ad, events) = await showRewarded(tester);
      ad.reward();
      ad.dismiss();
      expect(events, ['showed', 'rewarded:1', 'dismissed']);
    });

    testWidgets('reward reported after dismissal is delivered once', (
      tester,
    ) async {
      final (ad, events) = await showRewarded(tester);
      ad.dismiss();
      ad.reward();
      ad.reward();
      expect(events, ['showed', 'dismissed', 'rewarded:1']);
    });

    testWidgets('duplicate rewards are delivered once', (tester) async {
      final (ad, events) = await showRewarded(tester);
      ad.reward();
      ad.reward();
      ad.reward();
      ad.dismiss();
      expect(events.where((e) => e.startsWith('rewarded')), hasLength(1));
    });

    testWidgets('dismissal without reward grants nothing', (tester) async {
      final (ad, events) = await showRewarded(tester);
      ad.dismiss();
      ad.dismiss();
      expect(events, ['showed', 'dismissed']);
    });

    testWidgets('rewarded interstitial follows the same rules', (tester) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeRewardedInterstitial();
      h.onRewardedInt = (cb) => cb.onAdLoaded(ad);
      final events = <String>[];
      await manager.showRewardedInterstitial(
        ctx,
        0,
        RewardedCallbacks(
          onRewarded: (_) => events.add('rewarded'),
          onDismissed: () => events.add('dismissed'),
        ),
      );
      ad.reward();
      ad.reward();
      ad.dismiss();
      ad.dismiss();
      expect(events, ['rewarded', 'dismissed']);
      expect(ad.disposed, 1);
    });
  });

  group('asynchronous show failures', () {
    testWidgets('async show() error: one error, ad disposed, lock released', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeInterstitial()..showError = StateError('async boom');
      var first = true;
      h.onInterstitial = (cb) {
        cb.onAdLoaded(first ? ad : FakeInterstitial());
        first = false;
      };
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      await tester.pump();
      expect(rec.errors, hasLength(1));
      expect(ad.disposed, 1);

      ad.failToShow();
      ad.dismiss();
      expect(rec.errors, hasLength(1));
      expect(rec.success, 0);

      final next = Recorder();
      await manager.showInterstitial(ctx, 0, next);
      expect(next.errors, isEmpty);
    });

    testWidgets('synchronous throw from show() is reported once', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeSyncThrowInterstitial();
      var first = true;
      h.onInterstitial = (cb) {
        cb.onAdLoaded(first ? ad : FakeInterstitial());
        first = false;
      };
      final rec = Recorder();
      await manager.showInterstitial(ctx, 0, rec);
      expect(rec.errors, hasLength(1));
      expect(ad.disposed, 1);

      final next = Recorder();
      await manager.showInterstitial(ctx, 0, next);
      expect(next.errors, isEmpty);
    });

    testWidgets('rewarded: show failure reports onFailedToShow once', (
      tester,
    ) async {
      await setUpManager();
      final ctx = await pumpHost(tester);
      final ad = FakeRewarded();
      h.onRewarded = (cb) => cb.onAdLoaded(ad);
      var failures = 0;
      var dismissed = 0;
      await manager.showRewarded(
        ctx,
        0,
        RewardedCallbacks(
          onFailedToShow: (_) => failures++,
          onDismissed: () => dismissed++,
        ),
      );
      ad.fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
        ad,
        AdError(1, 'd', 'x'),
      );
      ad.dismiss();
      expect(failures, 1);
      expect(dismissed, 0);
      expect(ad.disposed, 1);
    });
  });
}
