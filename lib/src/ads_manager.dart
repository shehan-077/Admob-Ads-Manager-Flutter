import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_ids.dart';
import 'ads_sdk.dart';
import 'ads_status.dart';
import 'banner_types.dart';
import 'ads_unit.dart';
import 'banner_config.dart';
import 'ad_preload_cache.dart';
import 'loading_overlay.dart';
import 'request_handler.dart';

class _LifecycleWatcher with WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onChange;

  _LifecycleWatcher(this.onChange);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}

class _FullScreenOp {}

/// A request to retry failed banner / native loads. See
/// [AdsManager.retryFailedAds].
class AdRetryRequest {
  final int id;
  final AdsUnit? unit;
  final int? index;

  const AdRetryRequest._(this.id, this.unit, this.index);

  /// Whether this request addresses a widget of [widgetUnit] at [widgetIndex].
  bool matches(AdsUnit widgetUnit, int widgetIndex) =>
      (unit == null || unit == widgetUnit) &&
      (index == null || index == widgetIndex);
}

class AdsManager {
  static final AdsManager _instance = AdsManager._internal();
  factory AdsManager() => _instance;
  static AdsManager get instance => _instance;
  AdsManager._internal();

  AdMobIds? _ids;
  AdsStatus _status = AdsStatus.enabled;
  bool _forceTestAds = false;
  AdsConsentMode _consentMode = AdsConsentMode.managed;
  Future<void>? _sdkInit;
  Future<void>? _consentFuture;
  Future<bool>? _privacyFuture;
  bool _consentRunning = false;
  bool _consentUpdateFailed = false;
  ConsentRequestParameters? _consentParams;
  bool _sdkReady = false;
  int _refreshSeq = 0;
  int _retryCounter = 0;
  _FullScreenOp? _activeOp;

  int _epoch = 0;

  AdsSdk _sdk = AdsSdk();
  AdPreloadCache _cache = AdPreloadCache();
  final LoadingOverlay _loadingOverlay = LoadingOverlay();
  final Map<String, Future<void>> _loadingTasks = {};
  final Set<(AdsUnit, int)> _pendingPreloads = {};
  final ValueNotifier<bool> _available = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _privacyRequired = ValueNotifier<bool>(false);
  final ValueNotifier<AdRetryRequest?> _retryRequests =
      ValueNotifier<AdRetryRequest?>(null);

  /// Maximum time to wait for an ad request before reporting an error.
  /// An ad that arrives after the timeout is cached for later use (or
  /// disposed if it became obsolete); it is never shown by the timed-out call.
  Duration loadTimeout = const Duration(seconds: 15);

  /// Maximum time [whenReady] / the start-up flow waits for
  /// `MobileAds.initialize()`. After it elapses ads stay unavailable until
  /// [refreshAvailability] succeeds; a late initialization is not lost.
  Duration sdkInitTimeout = const Duration(seconds: 30);

  /// How long a full-screen request waits for the app to become `resumed` when
  /// the lifecycle state is `inactive` before it is refused.
  Duration foregroundWait = const Duration(seconds: 2);

  /// SDK seam. Internal, used by the widgets and tests.
  @internal
  AdsSdk get sdk => _sdk;

  /// Whether ads can be requested right now: configured, not disabled, the
  /// Mobile Ads SDK is initialized and, in [AdsConsentMode.managed], the UMP
  /// SDK's `canRequestAds` is true. Banner and native widgets listen to this.
  ///
  /// Three different facts, three different members:
  /// * consent processing finished -> [consentReady];
  /// * the SDK finished initializing -> [isSdkInitialized];
  /// * ads can be requested now -> this listenable / [whenReady].
  ValueListenable<bool> get adsAvailable => _available;

  /// True once `MobileAds.initialize()` has completed successfully.
  bool get isSdkInitialized => _sdkReady;

  /// True when the user must be offered a privacy-options entry point.
  /// Updated after the consent flow and after the privacy options form.
  ValueListenable<bool> get privacyOptionsRequired => _privacyRequired;

  /// Completes when the start-up consent processing has settled: the consent
  /// information update and form (managed mode) and the eligibility check
  /// that follows, including the SDK initialization attempt. It never throws
  /// and completes immediately when no flow was started (external mode,
  /// disabled ads, or [init] not called yet).
  ///
  /// It does **not** promise that ads can be requested: the user may have
  /// declined, or initialization may have failed. Use [whenReady] or
  /// [adsAvailable] for that.
  Future<void> get consentReady => _consentFuture ?? Future<void>.value();

  /// Completes after [consentReady] with whether ads can be requested right
  /// now (the value of [adsAvailable]). Never throws, and never waits for
  /// anything but the start-up flow, so it cannot hang when ads are disabled
  /// or consent is denied.
  Future<bool> whenReady() async {
    await consentReady;
    return _available.value;
  }

  /// Re-evaluates consent eligibility and retries SDK initialization, for
  /// example after a failed initialization. In managed mode, if the start-up
  /// consent information update failed (for example the device was offline),
  /// the update and form are attempted again first. Returns [adsAvailable].
  /// Never throws.
  Future<bool> refreshAvailability() async {
    if (!isConfigured || isDisabled) return false;
    await consentReady;
    while (_consentRunning) {
      await consentReady;
    }
    final params = _consentParams;
    if (_consentMode == AdsConsentMode.managed &&
        _consentUpdateFailed &&
        params != null) {
      await (_consentFuture = _runConsent(params));
      return _available.value;
    }
    try {
      await _refreshEligibility();
    } catch (e) {
      debugPrint('Ad availability refresh failed: $e');
    }
    return _available.value;
  }

  /// True while the start-up consent flow (including its form) is running.
  bool get consentInProgress => _consentRunning;

  /// Asks every banner / native widget that currently has **no ad because its
  /// last load failed** to try once more. Widgets that hold an ad, are still
  /// loading, or cannot request ads (ads disabled, SDK not initialized,
  /// consent missing) ignore the request; nothing is retried automatically.
  /// Limit the request with [unit] (`AdsUnit.banner` or `AdsUnit.native`) and
  /// [index].
  void retryFailedAds({AdsUnit? unit, int? index}) {
    _retryRequests.value = AdRetryRequest._(++_retryCounter, unit, index);
  }

  /// Retry requests, consumed by the banner / native widgets.
  @internal
  ValueListenable<AdRetryRequest?> get retryRequests => _retryRequests;

  /// Replaces the SDK seam and resets all state. Tests only.
  @visibleForTesting
  void resetForTesting({AdsSdk? sdk, AdPreloadCache? cache}) {
    _cache.clear();
    _loadingOverlay.hide();
    _loadingTasks.clear();
    _pendingPreloads.clear();
    _ids = null;
    _status = AdsStatus.enabled;
    _forceTestAds = false;
    _consentMode = AdsConsentMode.managed;
    _sdkInit = null;
    _sdkReady = false;
    _consentFuture = null;
    _privacyFuture = null;
    _consentRunning = false;
    _consentUpdateFailed = false;
    _consentParams = null;
    _refreshSeq++;
    _activeOp = null;
    _epoch++;
    _available.value = false;
    _privacyRequired.value = false;
    loadTimeout = const Duration(seconds: 15);
    sdkInitTimeout = const Duration(seconds: 30);
    foregroundWait = const Duration(seconds: 2);
    _sdk = sdk ?? AdsSdk();
    _cache = cache ?? AdPreloadCache();
  }

  /// Configures the manager.
  ///
  /// With the default [AdsConsentMode.managed] this returns as soon as the
  /// configuration is applied: the UMP flow (consent info update on every
  /// launch, then the consent form if required) runs in the background, so
  /// calling this before `runApp` never waits for a form. Ads are requested
  /// only after the SDK reports `canRequestAds`; use [consentReady] or
  /// [adsAvailable] to observe progress. `preLoad` calls made earlier are
  /// remembered and run once ads become available.
  ///
  /// With [AdsConsentMode.external] the app owns UMP; this awaits the Mobile
  /// Ads SDK initialization and does not gate requests.
  ///
  /// [consentDebugSettings] (debug geography / test devices) is honoured in
  /// non-release builds only.
  Future<void> init({
    required AdMobIds ids,
    required AdsStatus status,
    Color? loadingColor,
    AdsConsentMode consentMode = AdsConsentMode.managed,
    ConsentDebugSettings? consentDebugSettings,
    bool? tagForUnderAgeOfConsent,
  }) async {
    _ids = ids;
    _status = status;
    _consentMode = consentMode;

    if (loadingColor != null) {
      _loadingOverlay.setColor(loadingColor);
    }

    if (isDisabled) {
      _invalidateAds();
      _pendingPreloads.clear();
      _available.value = false;
      _privacyRequired.value = false;
      return;
    }

    if (consentMode == AdsConsentMode.external) {
      await _refreshEligibility(rethrowInitError: true);
      return;
    }

    _consentParams = ConsentRequestParameters(
      tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
      consentDebugSettings: _debugSettingsOrNull(consentDebugSettings),
    );
    _consentFuture ??= _runConsent(_consentParams!);
  }

  ConsentDebugSettings? _debugSettingsOrNull(ConsentDebugSettings? settings) {
    if (settings == null) return null;
    if (kReleaseMode) {
      debugPrint(
        'AdsManager: consentDebugSettings are ignored in release builds.',
      );
      return null;
    }
    return settings;
  }

  Future<void> _runConsent(ConsentRequestParameters params) async {
    _consentRunning = true;
    _consentUpdateFailed = false;
    try {
      final updateError = await _sdk.requestConsentInfoUpdate(params);
      if (updateError != null) {
        _consentUpdateFailed = true;
        debugPrint('UMP consent info update failed: ${updateError.message}');
      } else {
        final formError = await _sdk.loadAndShowConsentFormIfRequired();
        if (formError != null) {
          debugPrint('UMP consent form failed: ${formError.message}');
        }
      }
    } catch (e) {
      _consentUpdateFailed = true;
      debugPrint('UMP consent flow failed: $e');
    } finally {
      _consentRunning = false;
    }
    try {
      await _refreshEligibility();
    } catch (e) {
      debugPrint('Ad eligibility refresh failed: $e');
    }
  }

  Future<void> _refreshEligibility({bool rethrowInitError = false}) async {
    final seq = ++_refreshSeq;

    var canRequest = true;
    if (_consentMode == AdsConsentMode.managed) {
      try {
        canRequest = await _sdk.canRequestAds();
      } catch (e) {
        debugPrint('canRequestAds() failed: $e');
        canRequest = false;
      }
    }
    if (seq != _refreshSeq) return;

    if (!canRequest || isDisabled) {
      _invalidateAds();
      _pendingPreloads.clear();
      _available.value = false;
    } else {
      try {
        await _awaitSdkInit();
        if (seq != _refreshSeq) return;
        _available.value = isConfigured;
      } catch (e) {
        if (seq != _refreshSeq) return;
        _available.value = false;
        debugPrint('Mobile Ads SDK initialization failed: $e');
        if (rethrowInitError) rethrow;
      }
    }

    await _updatePrivacyRequirement();
    if (seq != _refreshSeq) return;
    if (kDebugMode) {
      debugPrint(
        'AdsManager: canRequestAds=$canRequest sdkInitialized=$_sdkReady '
        'available=${_available.value} privacyOptionsRequired='
        '${_privacyRequired.value}',
      );
    }

    if (_available.value) {
      final pending = _pendingPreloads.toList();
      _pendingPreloads.clear();
      for (final (unit, index) in pending) {
        _preloadQuietly(unit, index);
      }
    }
  }

  Future<void> _updatePrivacyRequirement() async {
    try {
      _privacyRequired.value = await _sdk.isPrivacyOptionsRequired();
    } catch (_) {
      _privacyRequired.value = false;
    }
  }

  void _invalidateAds() {
    _epoch++;
    _cache.clear();
  }

  Future<void> _ensureSdkInitialized() {
    final existing = _sdkInit;
    if (existing != null) return existing;
    final future = _sdk.initialize();
    _sdkInit = future;
    future.then<void>(
      (_) {
        if (identical(_sdkInit, future)) _sdkReady = true;
      },
      onError: (Object _) {
        if (identical(_sdkInit, future)) _sdkInit = null;
      },
    );
    return future;
  }

  Future<void> _awaitSdkInit() => _ensureSdkInitialized().timeout(
    sdkInitTimeout,
    onTimeout: () => throw TimeoutException(
      'Mobile Ads SDK initialization timed out',
      sdkInitTimeout,
    ),
  );

  Future<bool> _requestsAllowed() async {
    if (_consentMode == AdsConsentMode.external) return true;
    try {
      return await _sdk.canRequestAds();
    } catch (_) {
      return false;
    }
  }

  /// Whether the privacy options entry point must be shown (live query).
  Future<bool> isPrivacyOptionsRequired() async {
    await _updatePrivacyRequirement();
    return _privacyRequired.value;
  }

  /// Shows the UMP privacy options form and then re-evaluates eligibility.
  /// If the user's choices no longer allow ad requests, cached ads are
  /// disposed, in-flight requests become obsolete and banner / native widgets
  /// remove their ads; a full-screen ad already on screen is left to finish.
  /// Concurrent calls share one form. Returns true if the form completed
  /// without error.
  Future<bool> showPrivacyOptionsForm() {
    final existing = _privacyFuture;
    if (existing != null) return existing;
    final future = _showPrivacyOptions().whenComplete(() {
      _privacyFuture = null;
    });
    _privacyFuture = future;
    return future;
  }

  Future<bool> _showPrivacyOptions() async {
    await consentReady;
    FormError? error;
    try {
      error = await _sdk.showPrivacyOptionsForm();
    } catch (e) {
      debugPrint('UMP privacy options form failed: $e');
      return false;
    }
    if (error != null) {
      debugPrint('UMP privacy options form failed: ${error.message}');
    }
    try {
      await _refreshEligibility();
    } catch (e) {
      debugPrint('Ad eligibility refresh failed: $e');
    }
    return error == null;
  }

  /// Development only: clears stored consent so the flow behaves like a first
  /// install. Throws outside debug builds; call [init] again afterwards.
  Future<void> debugResetConsent() async {
    if (!kDebugMode) {
      throw StateError(
        'debugResetConsent() is only available in debug builds.',
      );
    }
    await _sdk.resetConsent();
    _consentFuture = null;
    _invalidateAds();
    _available.value = false;
    _privacyRequired.value = false;
  }

  void setForceTestAds(bool force) => _forceTestAds = force;
  void setLoadingColor(Color color) => _loadingOverlay.setColor(color);

  AdsStatus _effectiveStatus() {
    if (_status == AdsStatus.hybrid) {
      return (kDebugMode || _forceTestAds)
          ? AdsStatus.testing
          : AdsStatus.enabled;
    }
    return _status;
  }

  bool get isDisabled => _effectiveStatus() == AdsStatus.disabled;

  bool get _adsDisabled => isDisabled;

  /// True once [init] has been called with ids.
  bool get isConfigured => _ids != null;

  String _pickId(List<String> ids, int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must not be negative');
    }
    if (ids.isEmpty) {
      throw StateError('No AdMob IDs configured for this ad type');
    }
    return ids[index % ids.length];
  }

  /// Banner ad unit for [index]. In testing mode this is Google's sample
  /// unit for the banner [type] (collapsible banners have their own, and fixed
  /// banners use the fixed-size banner unit on iOS).
  String getBannerAdUnitId(
    int index, {
    BannerAdsType type = BannerAdsType.normal,
  }) {
    if (_effectiveStatus() == AdsStatus.testing &&
        type == BannerAdsType.collapsible) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return 'ca-app-pub-3940256099942544/2014213617';
        case TargetPlatform.iOS:
          return 'ca-app-pub-3940256099942544/8388050270';
        default:
          throw UnsupportedError(
            'AdMob test ads are only available on Android and iOS.',
          );
      }
    }
    if (_effectiveStatus() == AdsStatus.testing &&
        type == BannerAdsType.fixed &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    return getAdUnitId(AdsUnit.banner, index);
  }

  String getAdUnitId(AdsUnit unit, int index) {
    final effective = _effectiveStatus();

    if (effective == AdsStatus.testing) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
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
        case TargetPlatform.iOS:
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
        default:
          throw UnsupportedError(
            'AdMob test ads are only available on Android and iOS.',
          );
      }
    }

    final ids = _ids;
    if (ids == null) {
      throw StateError('AdsManager not initialized. Call init() first.');
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

  String _taskKey(AdsUnit unit, int index) => '${unit.name}#$index';

  /// Loads a full-screen ad into the cache so a later `show*` call is
  /// instant. Does nothing if ads are disabled, a fresh ad is already cached
  /// or a request for the same slot is in flight.
  ///
  /// Never throws for load failures (offline, no fill, timeout, consent not
  /// yet granted): they are logged and the future completes normally, so
  /// `await preLoad(...)` during start-up cannot break the app.
  Future<void> preLoad(AdsUnit unit, int index) async {
    if (!_adsDisabled &&
        _consentMode == AdsConsentMode.managed &&
        _consentRunning &&
        (unit != AdsUnit.banner && unit != AdsUnit.native)) {
      _pendingPreloads.add((unit, index));
      return;
    }
    try {
      await _load(unit, index);
    } catch (e) {
      debugPrint('Preload of ${unit.name}#$index failed: $e');
    }
  }

  void _preloadQuietly(AdsUnit unit, int index) {
    unawaited(preLoad(unit, index));
  }

  Future<void> _load(AdsUnit unit, int index) {
    if (_adsDisabled) return Future.value();

    switch (unit) {
      case AdsUnit.banner:
      case AdsUnit.native:
        return Future.value();
      case AdsUnit.interstitial:
      case AdsUnit.rewarded:
      case AdsUnit.rewardedInt:
      case AdsUnit.appOpen:
        return _runSingleLoad(unit, index, () => _request(unit, index));
    }
  }

  Future<void> _runSingleLoad(
    AdsUnit unit,
    int index,
    Future<void> Function() loader,
  ) {
    final key = _taskKey(unit, index);
    final existing = _loadingTasks[key];
    if (existing != null) return existing;

    final future = loader().whenComplete(() {
      _loadingTasks.remove(key);
    });

    _loadingTasks[key] = future;
    return future;
  }

  Future<void> _request(AdsUnit unit, int index) async {
    if (_ids == null) {
      throw StateError('AdsManager not initialized. Call init() first.');
    }
    if (_cache.contains(unit, index)) return;
    final epoch = _epoch;

    if (!await _requestsAllowed()) {
      throw StateError('Ads cannot be requested: user consent not granted.');
    }
    await _awaitSdkInit();
    if (_adsDisabled || epoch != _epoch) return;

    final id = getAdUnitId(unit, index);
    final completer = Completer<void>();

    void onLoaded(Ad ad) {
      if (_adsDisabled || epoch != _epoch) {
        disposeAdOnce(ad);
      } else {
        _cache.set(unit, index, ad);
      }
      if (!completer.isCompleted) completer.complete();
    }

    void onFailed(LoadAdError error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    switch (unit) {
      case AdsUnit.interstitial:
        _sdk.loadInterstitial(
          id,
          InterstitialAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        );
      case AdsUnit.appOpen:
        _sdk.loadAppOpen(
          id,
          AppOpenAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        );
      case AdsUnit.rewarded:
        _sdk.loadRewarded(
          id,
          RewardedAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        );
      case AdsUnit.rewardedInt:
        _sdk.loadRewardedInterstitial(
          id,
          RewardedInterstitialAdLoadCallback(
            onAdLoaded: onLoaded,
            onAdFailedToLoad: onFailed,
          ),
        );
      case AdsUnit.banner:
      case AdsUnit.native:
        return;
    }

    await completer.future.timeout(
      loadTimeout,
      onTimeout: () => throw TimeoutException(
        'Timed out loading ${unit.name} ad',
        loadTimeout,
      ),
    );
  }

  Future<void> _showFullScreen<T extends Ad>({
    required BuildContext context,
    required AdsUnit unit,
    required int index,
    required void Function() onDisabled,
    required void Function(Object error) onError,
    void Function()? onLoaded,
    void Function(Object error)? onLoadFailed,
    required void Function(T ad, _FullScreenOp op) present,
  }) async {
    if (_adsDisabled) {
      onDisabled();
      return;
    }
    if (_consentMode == AdsConsentMode.managed && _consentRunning) {
      onError('Ads are not available yet: the consent flow is in progress.');
      return;
    }
    if (!await _awaitForeground()) {
      onError('The app is not in the foreground: no full-screen ad is shown.');
      return;
    }
    if (_adsDisabled) {
      onDisabled();
      return;
    }
    if (_activeOp != null) {
      onError('Another full-screen ad is already loading or showing.');
      return;
    }
    if (!context.mounted) {
      onError('Context is no longer mounted.');
      return;
    }

    final op = _FullScreenOp();
    _activeOp = op;
    var handedOff = false;
    try {
      if (!await _requestsAllowed()) {
        _invalidateAds();
        onError('Ads cannot be requested: user consent not granted.');
        return;
      }
      if (!context.mounted) {
        onError('Context is no longer mounted.');
        return;
      }

      if (!_cache.contains(unit, index)) {
        _loadingOverlay.show(context);
        try {
          await _load(unit, index);
        } catch (e) {
          onLoadFailed?.call(e);
          onError(e);
          return;
        } finally {
          _loadingOverlay.hide();
        }
        if (_cache.contains(unit, index)) onLoaded?.call();
      }

      if (_adsDisabled) {
        onDisabled();
        return;
      }
      if (!context.mounted) {
        onError('Context is no longer mounted.');
        return;
      }
      if (!await _awaitForeground()) {
        onError(
          'The app is not in the foreground: no full-screen ad is shown.',
        );
        return;
      }
      if (_adsDisabled) {
        onDisabled();
        return;
      }

      final ad = _cache.take<T>(unit, index);
      if (ad == null) {
        onError('Failed to load ${unit.name} ad');
        return;
      }

      handedOff = true;
      present(ad, op);
    } finally {
      if (!handedOff) _releaseLock(op);
    }
  }

  /// Whether the app is in the foreground. A full-screen ad is only started
  /// while the lifecycle state is `resumed`. `inactive` (a system dialog, or
  /// another activity such as an ad the SDK restored after the Android
  /// Activity was recreated) is given [foregroundWait] to become `resumed`;
  /// `paused`, `hidden` and `detached` are refused at once. This keeps an
  /// automatic ad from stacking on top of an ad that is already on screen.
  Future<bool> _awaitForeground() async {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return true;
    if (state != AppLifecycleState.inactive) return false;

    final result = Completer<bool>();
    final observer = _LifecycleWatcher((next) {
      if (result.isCompleted || next == AppLifecycleState.inactive) return;
      result.complete(next == AppLifecycleState.resumed);
    });
    binding.addObserver(observer);
    final timer = Timer(foregroundWait, () {
      if (!result.isCompleted) result.complete(false);
    });
    try {
      return await result.future;
    } finally {
      timer.cancel();
      binding.removeObserver(observer);
    }
  }

  void _releaseLock(_FullScreenOp op) {
    if (identical(_activeOp, op)) _activeOp = null;
  }

  void _runShow(Future<void> Function() show, void Function(Object) fail) {
    try {
      show().catchError((Object e) {
        fail(e);
      });
    } catch (e) {
      fail(e);
    }
  }

  void _release(Ad ad, AdsUnit unit, int index, _FullScreenOp op) {
    disposeAdOnce(ad);
    _releaseLock(op);
    _preloadQuietly(unit, index);
  }

  Future<void> showInterstitial(
    BuildContext context,
    int index,
    RequestHandler handler,
  ) {
    return _showFullScreen<InterstitialAd>(
      context: context,
      unit: AdsUnit.interstitial,
      index: index,
      onDisabled: handler.onSuccess,
      onError: (e) => handler.onError(e.toString()),
      present: (ad, op) {
        var done = false;
        void finish(void Function() notify) {
          if (done) return;
          done = true;
          _release(ad, AdsUnit.interstitial, index, op);
          notify();
        }

        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (_) => finish(handler.onSuccess),
          onAdFailedToShowFullScreenContent: (_, error) =>
              finish(() => handler.onError(error.toString())),
        );
        _runShow(ad.show, (e) => finish(() => handler.onError(e.toString())));
      },
    );
  }

  Future<void> showAppOpen(
    BuildContext context,
    int index,
    RequestHandler handler,
  ) {
    return _showFullScreen<AppOpenAd>(
      context: context,
      unit: AdsUnit.appOpen,
      index: index,
      onDisabled: handler.onSuccess,
      onError: (e) => handler.onError(e.toString()),
      present: (ad, op) {
        var done = false;
        void finish(void Function() notify) {
          if (done) return;
          done = true;
          _release(ad, AdsUnit.appOpen, index, op);
          notify();
        }

        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (_) => finish(handler.onSuccess),
          onAdFailedToShowFullScreenContent: (_, error) =>
              finish(() => handler.onError(error.toString())),
        );
        _runShow(ad.show, (e) => finish(() => handler.onError(e.toString())));
      },
    );
  }

  /// Shows a rewarded ad. [RewardedCallbacks.onRewarded] fires at most once
  /// per ad, only from the SDK's user-earned-reward callback.
  Future<void> showRewarded(
    BuildContext context,
    int index,
    RewardedCallbacks handler,
  ) {
    return _showFullScreen<RewardedAd>(
      context: context,
      unit: AdsUnit.rewarded,
      index: index,
      onDisabled: () => handler.onDismissed?.call(),
      onError: (e) => handler.onError?.call(e),
      onLoaded: () => handler.onLoaded?.call(),
      onLoadFailed: (e) => handler.onFailedToLoad?.call(e),
      present: (ad, op) {
        var done = false;
        var rewarded = false;
        void finish(void Function() notify) {
          if (done) return;
          done = true;
          _release(ad, AdsUnit.rewarded, index, op);
          notify();
        }

        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdShowedFullScreenContent: (_) => handler.onShowed?.call(),
          onAdDismissedFullScreenContent: (_) =>
              finish(() => handler.onDismissed?.call()),
          onAdFailedToShowFullScreenContent: (_, error) =>
              finish(() => handler.onFailedToShow?.call(error)),
        );
        _runShow(
          () => ad.show(
            onUserEarnedReward: (_, reward) {
              if (rewarded) return;
              rewarded = true;
              handler.onRewarded?.call(reward);
            },
          ),
          (e) => finish(() => handler.onFailedToShow?.call(e)),
        );
      },
    );
  }

  /// Shows a rewarded interstitial ad. Reward semantics match [showRewarded].
  Future<void> showRewardedInterstitial(
    BuildContext context,
    int index,
    RewardedCallbacks handler,
  ) {
    return _showFullScreen<RewardedInterstitialAd>(
      context: context,
      unit: AdsUnit.rewardedInt,
      index: index,
      onDisabled: () => handler.onDismissed?.call(),
      onError: (e) => handler.onError?.call(e),
      onLoaded: () => handler.onLoaded?.call(),
      onLoadFailed: (e) => handler.onFailedToLoad?.call(e),
      present: (ad, op) {
        var done = false;
        var rewarded = false;
        void finish(void Function() notify) {
          if (done) return;
          done = true;
          _release(ad, AdsUnit.rewardedInt, index, op);
          notify();
        }

        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdShowedFullScreenContent: (_) => handler.onShowed?.call(),
          onAdDismissedFullScreenContent: (_) =>
              finish(() => handler.onDismissed?.call()),
          onAdFailedToShowFullScreenContent: (_, error) =>
              finish(() => handler.onFailedToShow?.call(error)),
        );
        _runShow(
          () => ad.show(
            onUserEarnedReward: (_, reward) {
              if (rewarded) return;
              rewarded = true;
              handler.onRewarded?.call(reward);
            },
          ),
          (e) => finish(() => handler.onFailedToShow?.call(e)),
        );
      },
    );
  }
}
