import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_ids.dart';
import 'ads_status.dart';
import 'ads_unit.dart';
import 'ad_preload_cache.dart';
import 'loading_overlay.dart';
import 'request_handler.dart';

class AdsManager {
  static final AdsManager _instance = AdsManager._internal();

  factory AdsManager() => _instance;
  static AdsManager get instance => _instance;

  AdsManager._internal();

  AdMobIds? _ids;
  AdsStatus _status = AdsStatus.enabled;
  bool _forceTestAds = false;

  final AdPreloadCache _cache = AdPreloadCache();
  final LoadingOverlay _loadingOverlay = LoadingOverlay();

  bool _initialized = false;

  Future<void> init({
    required AdMobIds ids,
    required AdsStatus status,
    Color? loadingColor,
  }) async {
    _ids = ids;
    _status = status;

    if (loadingColor != null) {
      _loadingOverlay.setColor(loadingColor);
    }

    if (!_initialized) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }
  }

  void setForceTestAds(bool force) {
    _forceTestAds = force;
  }

  void setLoadingColor(Color color) {
    _loadingOverlay.setColor(color);
  }

  AdsStatus _effectiveStatus() {
    if (_status == AdsStatus.hybrid) {
      final debug = kDebugMode;
      return (debug || _forceTestAds) ? AdsStatus.testing : AdsStatus.enabled;
    }
    return _status;
  }

  String _pickId(List<String> ids, int index) {
    if (ids.isEmpty) {
      throw StateError('No AdMob IDs configured for this type');
    }
    if (index < 0 || index >= ids.length) {
      index = 0;
    }
    return ids[index];
  }

  String getAdUnitId(AdsUnit unit, int index) {
    final effective = _effectiveStatus();
    if (effective == AdsStatus.testing) {
      if (Platform.isAndroid) {
        switch (unit) {
          case AdsUnit.interstitial:
            return 'ca-app-pub-3940256099942544/1033173712';
          case AdsUnit.banner:
            return 'ca-app-pub-3940256099942544/6300978111';
          case AdsUnit.appOpen:
            return 'ca-app-pub-3940256099942544/9257395921';
          case AdsUnit.rewarded:
            return 'ca-app-pub-3940256099942544/5224354917';
          case AdsUnit.native:
            return 'ca-app-pub-3940256099942544/2247696110';
          case AdsUnit.rewardedInt:
            return 'ca-app-pub-3940256099942544/5354046379';
        }
      } else if (Platform.isIOS) {
        switch (unit) {
          case AdsUnit.interstitial:
            return 'ca-app-pub-3940256099942544/4411468910';
          case AdsUnit.banner:
            return 'ca-app-pub-3940256099942544/2435281174';
          case AdsUnit.appOpen:
            return 'ca-app-pub-3940256099942544/5575463023';
          case AdsUnit.rewarded:
            return 'ca-app-pub-3940256099942544/1712485313';
          case AdsUnit.native:
            return 'ca-app-pub-3940256099942544/3986624511';
          case AdsUnit.rewardedInt:
            return 'ca-app-pub-3940256099942544/6978759866';
        }
      }
    }

    final ids = _ids;
    if (ids == null) {
      throw StateError('AdsManager not initialized. call init() first.');
    }

    switch (unit) {
      case AdsUnit.interstitial:
        return _pickId(ids.interstitialIds, index);
      case AdsUnit.banner:
        return _pickId(ids.bannerIds, index);
      case AdsUnit.appOpen:
        return _pickId(ids.appOpenIds, index);
      case AdsUnit.rewarded:
        return _pickId(ids.rewardedIds, index);
      case AdsUnit.native:
        return _pickId(ids.nativeIds, index);
      case AdsUnit.rewardedInt:
        return _pickId(ids.rewardedIntIds, index);
    }
  }

  bool get _adsDisabled => _effectiveStatus() == AdsStatus.disabled;

  Future<void> preLoad(AdsUnit unit, int index) async {
    if (_adsDisabled) return;

    switch (unit) {
      case AdsUnit.interstitial:
        await _preloadInterstitial(index);
        break;
      case AdsUnit.rewarded:
        await _preloadRewarded(index);
        break;
      case AdsUnit.rewardedInt:
        await _preloadRewardedInterstitial(index);
        break;
      case AdsUnit.appOpen:
        break;
      case AdsUnit.banner:
      case AdsUnit.native:
        break;
    }
  }

  Future<void> _preloadInterstitial(int index) async {
    final completer = Completer<void>();
    final id = getAdUnitId(AdsUnit.interstitial, index);

    await InterstitialAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _cache.set(AdsUnit.interstitial, index, ad);
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _preloadAppOpen(int index) async {
    final completer = Completer<void>();
    final id = getAdUnitId(AdsUnit.appOpen, index);

    await AppOpenAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _cache.set(AdsUnit.appOpen, index, ad);
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _preloadRewarded(int index) async {
    final completer = Completer<void>();
    final id = getAdUnitId(AdsUnit.rewarded, index);

    await RewardedAd.load(
      adUnitId: id,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _cache.set(AdsUnit.rewarded, index, ad);
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );
    return completer.future;
  }

  Future<void> _preloadRewardedInterstitial(int index) async {
    final completer = Completer<void>();
    final id = getAdUnitId(AdsUnit.rewardedInt, index);

    await RewardedInterstitialAd.load(
      adUnitId: id,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _cache.set(AdsUnit.rewardedInt, index, ad);
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );
    return completer.future;
  }

  Future<void> showInterstitial(
    BuildContext context,
    int index,
    RequestHandler handler,
  ) async {
    if (_adsDisabled) {
      handler.onError('Ads disabled');
      return;
    }

    InterstitialAd? ad = _cache.get<InterstitialAd>(
      AdsUnit.interstitial,
      index,
    );

    if (ad == null) {
      _loadingOverlay.show(context);
      try {
        await _preloadInterstitial(index);
        ad = _cache.get<InterstitialAd>(AdsUnit.interstitial, index);
        _loadingOverlay.hide();
      } catch (e) {
        _loadingOverlay.hide();
        handler.onError(e.toString());
        return;
      }
    }

    if (ad == null) {
      handler.onError('Failed to load interstitial ad');
      return;
    }

    if (!context.mounted) {
      ad.dispose();
      _cache.remove(AdsUnit.interstitial, index);
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {},
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _cache.remove(AdsUnit.interstitial, index);
        handler.onSuccess();
        AdsManager.instance.preLoad(AdsUnit.interstitial, index);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _cache.remove(AdsUnit.interstitial, index);
        handler.onError(error.message);
      },
    );

    ad.show();
  }

  Future<void> showAppOpen(
    BuildContext context,
    int index,
    RequestHandler handler,
  ) async {
    if (_adsDisabled) {
      handler.onError('Ads disabled');
      return;
    }

    AppOpenAd? ad = _cache.get<AppOpenAd>(AdsUnit.appOpen, index);

    if (ad == null) {
      _loadingOverlay.show(context);
      try {
        await _preloadAppOpen(index);
        ad = _cache.get<AppOpenAd>(AdsUnit.appOpen, index);
        _loadingOverlay.hide();
      } catch (e) {
        _loadingOverlay.hide();
        handler.onError(e.toString());
        return;
      }
    }

    if (ad == null) {
      handler.onError('Failed to load interstitial ad');
      return;
    }

    if (!context.mounted) {
      ad.dispose();
      _cache.remove(AdsUnit.appOpen, index);
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {},
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _cache.remove(AdsUnit.interstitial, index);
        handler.onSuccess();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _cache.remove(AdsUnit.interstitial, index);
        handler.onError(error.message);
      },
    );

    ad.show();
  }

  Future<void> showRewarded(
    BuildContext context,
    int index,
    RewardedRequestHandler handler,
  ) async {
    if (_adsDisabled) {
      handler.onError('Ads disabled');
      return;
    }

    RewardedAd? ad = _cache.get<RewardedAd>(AdsUnit.rewarded, index);

    if (ad == null) {
      _loadingOverlay.show(context);
      try {
        await _preloadRewarded(index);
        ad = _cache.get<RewardedAd>(AdsUnit.rewarded, index);
        _loadingOverlay.hide();
      } catch (e) {
        _loadingOverlay.hide();
        handler.onError(e.toString());
        return;
      }
    }

    if (ad == null) {
      handler.onError('Failed to load rewarded ad');
      return;
    }

    if (!context.mounted) {
      ad.dispose();
      _cache.remove(AdsUnit.rewarded, index);
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        handler.onShowed();
        AdsManager.instance.preLoad(AdsUnit.rewarded, index);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _cache.remove(AdsUnit.rewarded, index);
        handler.onDismissed();
        AdsManager.instance.preLoad(AdsUnit.rewarded, index);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _cache.remove(AdsUnit.rewarded, index);
        handler.onFailedToShow(error.message);
      },
    );

    ad.show(
      onUserEarnedReward: (ad, reward) {
        handler.onRewarded();
      },
    );
  }

  Future<void> showRewardedInterstitial(
    BuildContext context,
    int index,
    RewardedRequestHandler handler,
  ) async {
    if (_adsDisabled) {
      handler.onError('Ads disabled');
      return;
    }

    RewardedInterstitialAd? ad = _cache.get<RewardedInterstitialAd>(
      AdsUnit.rewardedInt,
      index,
    );

    if (ad == null) {
      _loadingOverlay.show(context);
      try {
        await _preloadRewardedInterstitial(index);
        ad = _cache.get<RewardedInterstitialAd>(AdsUnit.rewardedInt, index);
        _loadingOverlay.hide();
      } catch (e) {
        _loadingOverlay.hide();
        handler.onError(e.toString());
        return;
      }
    }

    if (ad == null) {
      handler.onError('Failed to load rewarded interstitial ad');
      return;
    }

    if (!context.mounted) {
      ad.dispose();
      _cache.remove(AdsUnit.rewardedInt, index);
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        handler.onShowed();
        AdsManager.instance.preLoad(AdsUnit.rewardedInt, index);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _cache.remove(AdsUnit.rewardedInt, index);
        handler.onDismissed();
        AdsManager.instance.preLoad(AdsUnit.rewardedInt, index);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _cache.remove(AdsUnit.rewardedInt, index);
        handler.onFailedToShow(error.message);
      },
    );

    ad.show(
      onUserEarnedReward: (ad, reward) {
        handler.onRewarded();
      },
    );
  }
}
