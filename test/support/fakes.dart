import 'dart:async';

import 'package:admob_ads_manager/admob_ads_manager.dart';
import 'package:admob_ads_manager/src/ads_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FakeInterstitial implements InterstitialAd {
  @override
  FullScreenContentCallback<InterstitialAd>? fullScreenContentCallback;
  int shown = 0;
  int disposed = 0;
  Object? showError;

  @override
  Future<void> show() async {
    shown++;
    if (showError != null) throw showError!;
  }

  @override
  Future<void> dispose() async => disposed++;

  void dismiss() =>
      fullScreenContentCallback!.onAdDismissedFullScreenContent!(this);
  void failToShow() =>
      fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
        this,
        AdError(1, 'd', 'fail'),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSyncThrowInterstitial implements InterstitialAd {
  @override
  FullScreenContentCallback<InterstitialAd>? fullScreenContentCallback;
  int disposed = 0;

  @override
  Future<void> show() => throw StateError('sync boom');

  @override
  Future<void> dispose() async => disposed++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAppOpen implements AppOpenAd {
  @override
  FullScreenContentCallback<AppOpenAd>? fullScreenContentCallback;
  int shown = 0;
  int disposed = 0;

  @override
  Future<void> show() async => shown++;

  @override
  Future<void> dispose() async => disposed++;

  void dismiss() =>
      fullScreenContentCallback!.onAdDismissedFullScreenContent!(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRewarded implements RewardedAd {
  @override
  FullScreenContentCallback<RewardedAd>? fullScreenContentCallback;
  OnUserEarnedRewardCallback? earn;
  int disposed = 0;

  @override
  Future<void> show({
    required OnUserEarnedRewardCallback onUserEarnedReward,
  }) async {
    earn = onUserEarnedReward;
    fullScreenContentCallback?.onAdShowedFullScreenContent?.call(this);
  }

  @override
  Future<void> dispose() async => disposed++;

  void reward() => earn!(_FakeAdWithoutView(), RewardItem(1, 'coin'));
  void dismiss() =>
      fullScreenContentCallback!.onAdDismissedFullScreenContent!(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRewardedInterstitial implements RewardedInterstitialAd {
  @override
  FullScreenContentCallback<RewardedInterstitialAd>? fullScreenContentCallback;
  OnUserEarnedRewardCallback? earn;
  int shown = 0;
  int disposed = 0;

  @override
  Future<void> show({
    required OnUserEarnedRewardCallback onUserEarnedReward,
  }) async {
    shown++;
    earn = onUserEarnedReward;
  }

  @override
  Future<void> dispose() async => disposed++;

  void reward() => earn!(_FakeAdWithoutView(), RewardItem(1, 'coin'));
  void dismiss() =>
      fullScreenContentCallback!.onAdDismissedFullScreenContent!(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAdWithoutView implements AdWithoutView {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBanner implements BannerAd {
  FakeBanner(this.adUnitId, this.size, this.request, this.listener);

  @override
  final String adUnitId;
  @override
  final AdSize size;
  @override
  final AdRequest request;
  @override
  final BannerAdListener listener;

  int loads = 0;
  int disposed = 0;
  AdSize? platformSize;
  Completer<AdSize?>? platformGate;

  @override
  Future<void> load() async => loads++;

  @override
  Future<void> dispose() async => disposed++;

  @override
  Future<AdSize?> getPlatformAdSize() =>
      platformGate?.future ?? Future.value(platformSize);

  void fireLoaded() => listener.onAdLoaded!(this);
  void fireFailed() =>
      listener.onAdFailedToLoad!(this, LoadAdError(3, 'd', 'no fill', null));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNative implements NativeAd {
  FakeNative(this.adUnitId, this.listener, this.style);

  @override
  final String adUnitId;
  @override
  final NativeAdListener listener;
  final NativeTemplateStyle style;

  int loads = 0;
  int disposed = 0;

  @override
  Future<void> load() async => loads++;

  @override
  Future<void> dispose() async => disposed++;

  void fireLoaded() => listener.onAdLoaded!(this);
  void fireFailed() =>
      listener.onAdFailedToLoad!(this, LoadAdError(3, 'd', 'no fill', null));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  final sdk = AdsSdk();
  final order = <String>[];
  int initCount = 0;
  bool canRequest = true;
  bool canRequestThrows = false;
  bool privacyRequired = false;
  FormError? updateError;
  FormError? formError;
  FormError? privacyError;
  Completer<FormError?>? formGate;
  int consentUpdates = 0;
  int consentForms = 0;
  int privacyForms = 0;
  int resets = 0;
  ConsentRequestParameters? lastParams;
  Completer<void>? privacyGate;
  int initFailures = 0;
  Completer<void>? initGate;
  bool anchoredNull = false;
  Completer<void>? anchoredGate;

  int interstitialRequests = 0;
  int rewardedRequests = 0;
  int rewardedIntRequests = 0;
  int appOpenRequests = 0;

  final banners = <FakeBanner>[];
  final natives = <FakeNative>[];
  Orientation? lastOrientation;
  int? lastAnchoredWidth;
  int anchoredCalls = 0;

  void Function(InterstitialAdLoadCallback cb) onInterstitial = (cb) =>
      cb.onAdLoaded(FakeInterstitial());
  void Function(RewardedAdLoadCallback cb) onRewarded = (cb) =>
      cb.onAdLoaded(FakeRewarded());
  void Function(AppOpenAdLoadCallback cb) onAppOpen = (cb) =>
      cb.onAdLoaded(FakeAppOpen());
  void Function(RewardedInterstitialAdLoadCallback cb) onRewardedInt = (cb) =>
      cb.onAdLoaded(FakeRewardedInterstitial());

  int get totalRequests =>
      interstitialRequests +
      rewardedRequests +
      rewardedIntRequests +
      appOpenRequests +
      banners.length +
      natives.length;

  Harness() {
    sdk.initialize = () async {
      initCount++;
      order.add('initialize');
      if (initFailures > 0) {
        initFailures--;
        throw StateError('init failed');
      }
      await initGate?.future;
    };
    sdk.loadInterstitial = (id, cb) {
      interstitialRequests++;
      onInterstitial(cb);
    };
    sdk.loadRewarded = (id, cb) {
      rewardedRequests++;
      onRewarded(cb);
    };
    sdk.loadAppOpen = (id, cb) {
      appOpenRequests++;
      onAppOpen(cb);
    };
    sdk.loadRewardedInterstitial = (id, cb) {
      rewardedIntRequests++;
      onRewardedInt(cb);
    };
    sdk.requestConsentInfoUpdate = (p) async {
      consentUpdates++;
      lastParams = p;
      order.add('consentInfoUpdate');
      return updateError;
    };
    sdk.loadAndShowConsentFormIfRequired = () async {
      consentForms++;
      order.add('consentForm');
      final gate = formGate;
      if (gate != null) return gate.future;
      return formError;
    };
    sdk.canRequestAds = () async {
      if (canRequestThrows) throw StateError('platform error');
      return canRequest;
    };
    sdk.isPrivacyOptionsRequired = () async => privacyRequired;
    sdk.showPrivacyOptionsForm = () async {
      privacyForms++;
      order.add('privacyForm');
      await privacyGate?.future;
      return privacyError;
    };
    sdk.resetConsent = () async => resets++;
    sdk.anchoredAdaptiveSize = (orientation, width) async {
      anchoredCalls++;
      lastOrientation = orientation;
      lastAnchoredWidth = width;
      await anchoredGate?.future;
      if (anchoredNull) return null;
      return AnchoredAdaptiveBannerAdSize(
        orientation,
        width: width,
        height: 60,
      );
    };
    sdk.createBanner = (id, size, request, listener) {
      final banner = FakeBanner(id, size, request, listener);
      banners.add(banner);
      return banner;
    };
    sdk.createNative = (id, listener, style, options) {
      final native = FakeNative(id, listener, style);
      natives.add(native);
      return native;
    };
    sdk.adWidget = (ad) => SizedBox.expand(key: ValueKey('ad-${ad.hashCode}'));
  }
}

AdMobIds get testIds => AdMobIds(
  appId: 'app',
  interstitialIds: const ['int0', 'int1'],
  bannerIds: const ['ban0', 'ban1'],
  appOpenIds: const ['open'],
  rewardedIds: const ['rew'],
  nativeIds: const ['nat0', 'nat1'],
  rewardedIntIds: const ['rint'],
);

class Recorder extends RequestHandler {
  int success = 0;
  final errors = <String>[];
  @override
  void onSuccess() => success++;
  @override
  void onError(String error) => errors.add(error);
}

Future<BuildContext> pumpHost(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        },
      ),
    ),
  );
  return ctx;
}
