import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Thin seam over the Google Mobile Ads / UMP static APIs so the manager's
/// logic can be exercised in unit tests without a platform channel.
///
/// Not part of the public API.
class AdsSdk {
  Future<void> Function() initialize = () async {
    await MobileAds.instance.initialize();
  };

  void Function(String adUnitId, InterstitialAdLoadCallback callback)
  loadInterstitial = (id, cb) => InterstitialAd.load(
    adUnitId: id,
    request: const AdRequest(),
    adLoadCallback: cb,
  );

  void Function(String adUnitId, AppOpenAdLoadCallback callback) loadAppOpen =
      (id, cb) => AppOpenAd.load(
        adUnitId: id,
        request: const AdRequest(),
        adLoadCallback: cb,
      );

  void Function(String adUnitId, RewardedAdLoadCallback callback) loadRewarded =
      (id, cb) => RewardedAd.load(
        adUnitId: id,
        request: const AdRequest(),
        rewardedAdLoadCallback: cb,
      );

  void Function(String adUnitId, RewardedInterstitialAdLoadCallback callback)
  loadRewardedInterstitial = (id, cb) => RewardedInterstitialAd.load(
    adUnitId: id,
    request: const AdRequest(),
    rewardedInterstitialAdLoadCallback: cb,
  );

  /// Completes with null on success or the [FormError] on failure.
  Future<FormError?> Function(ConsentRequestParameters params)
  requestConsentInfoUpdate = (params) {
    final completer = Completer<FormError?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () => completer.complete(null),
      (error) => completer.complete(error),
    );
    return completer.future;
  };

  Future<FormError?> Function() loadAndShowConsentFormIfRequired = () {
    final completer = Completer<FormError?>();
    ConsentForm.loadAndShowConsentFormIfRequired(completer.complete);
    return completer.future;
  };

  Future<FormError?> Function() showPrivacyOptionsForm = () {
    final completer = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm(completer.complete);
    return completer.future;
  };

  Future<bool> Function() canRequestAds = () =>
      ConsentInformation.instance.canRequestAds();

  Future<bool> Function() isPrivacyOptionsRequired = () async =>
      (await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus()) ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> Function() resetConsent = () =>
      ConsentInformation.instance.reset();

  Future<AnchoredAdaptiveBannerAdSize?> Function(
    Orientation orientation,
    int width,
  )
  anchoredAdaptiveSize =
      AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation;

  BannerAd Function(
    String adUnitId,
    AdSize size,
    AdRequest request,
    BannerAdListener listener,
  )
  createBanner = (id, size, request, listener) =>
      BannerAd(adUnitId: id, size: size, request: request, listener: listener);

  NativeAd Function(
    String adUnitId,
    NativeAdListener listener,
    NativeTemplateStyle style,
    NativeAdOptions options,
  )
  createNative = (id, listener, style, options) => NativeAd(
    adUnitId: id,
    request: const AdRequest(),
    listener: listener,
    nativeTemplateStyle: style,
    nativeAdOptions: options,
  );

  Widget Function(AdWithView ad) adWidget = (ad) => AdWidget(ad: ad);
}
