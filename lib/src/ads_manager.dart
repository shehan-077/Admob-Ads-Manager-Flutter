import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_events.dart';
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

class _FullScreenOp {
  final int id;
  _FullScreenOp(this.id);
}

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
  int _opCounter = 0;
  int _presentations = 0;
  bool _eligible = false;
  DateTime? _lastRecoveryAttempt;
  DateTime? _lastResumeRetry;
  _LifecycleWatcher? _resumeObserver;
  final Set<(AdsUnit, int)> _loadingShows = {};

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

  /// How long a `show*` call waits for the start-up consent flow (managed
  /// mode) before it is refused. Consent is never bypassed: no ad is requested
  /// or shown until the SDK reports `canRequestAds`.
  Duration consentWait = const Duration(seconds: 3);

  /// Maximum time the consent information update may take. A hung update is
  /// treated as a failed one, so recovery stays possible.
  Duration consentUpdateTimeout = const Duration(seconds: 30);

  /// Minimum spacing of automatic recovery attempts (a repeated consent update
  /// after a failed one, and the retry of failed banner / native loads when
  /// the app returns to the foreground). It limits consent and ad *requests*;
  /// it never limits how often the host may show an ad.
  Duration recoveryInterval = const Duration(seconds: 30);

  /// How long a presented full-screen ad may take to report that it started
  /// showing. If it never does (neither shown, dismissed nor failed), the
  /// operation is failed and the lock released. An ad that did report showing
  /// is never released by a timer.
  Duration showStartTimeout = const Duration(seconds: 10);

  /// Whether banner / native widgets whose load failed are retried once when
  /// the app returns to the foreground (at most once per [recoveryInterval]).
  bool retryFailedAdsOnResume = true;

  /// Receives an [AdEvent] for every load request, load result, show and paid
  /// event of every format (for analytics). Exceptions it throws are caught.
  void Function(AdEvent event)? onAdEvent;

  /// Delays of the automatic retries of a failed banner / native load, e.g.
  /// `[2s, 4s, 8s]`. Each failed slot is retried after the next delay and
  /// gives up after the last one until [retryFailedAds] (or a new
  /// configuration) restarts it. Empty (the default) disables automatic
  /// retries.
  List<Duration> autoRetryBackoff = const [];

  /// Delivers [event] to [onAdEvent]. Internal.
  @internal
  void emit(AdEvent event) {
    final callback = onAdEvent;
    if (callback == null) return;
    try {
      callback(event);
    } catch (e) {
      debugPrint('onAdEvent handler failed: $e');
    }
  }

  void _attachPaid(Ad ad, AdsUnit unit, int index) {
    void paid(Ad _, double micros, PrecisionType precision, String currency) =>
        emit(
          AdEvent(
            type: AdEventType.paid,
            unit: unit,
            index: index,
            valueMicros: micros,
            currencyCode: currency,
            precision: precision.name,
          ),
        );
    // Revenue reporting is best effort: it must never stop an ad from being
    // cached (and fakes in tests do not implement the setter).
    try {
      if (ad is InterstitialAd) {
        ad.onPaidEvent = paid;
      } else if (ad is AppOpenAd) {
        ad.onPaidEvent = paid;
      } else if (ad is RewardedAd) {
        ad.onPaidEvent = paid;
      } else if (ad is RewardedInterstitialAd) {
        ad.onPaidEvent = paid;
      }
    } catch (e) {
      debugPrint('Could not attach the paid-event listener: $e');
    }
  }

  /// Clock used for recovery spacing. Tests only.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

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
    _loadingOverlay.hideAll();
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
    consentWait = const Duration(seconds: 3);
    consentUpdateTimeout = const Duration(seconds: 30);
    recoveryInterval = const Duration(seconds: 30);
    showStartTimeout = const Duration(seconds: 10);
    retryFailedAdsOnResume = true;
    onAdEvent = null;
    autoRetryBackoff = const [];
    clock = DateTime.now;
    _opCounter = 0;
    _presentations = 0;
    _eligible = false;
    _lastRecoveryAttempt = null;
    _lastResumeRetry = null;
    _loadingShows.clear();
    final observer = _resumeObserver;
    _resumeObserver = null;
    if (observer != null) {
      try {
        WidgetsBinding.instance.removeObserver(observer);
      } catch (_) {}
    }
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

    _ensureResumeObserver();

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
    _lastRecoveryAttempt = clock();
    try {
      final updateError = await _sdk
          .requestConsentInfoUpdate(params)
          .timeout(consentUpdateTimeout);
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
        // Unknown is not permission, but it is also not a withdrawal: keep
        // what is cached and shown, and let a later attempt re-check.
        debugPrint('canRequestAds() failed: $e');
        if (seq != _refreshSeq) return;
        _consentUpdateFailed = true;
        return;
      }
    }
    if (seq != _refreshSeq) return;
    _eligible = canRequest && !isDisabled;

    if (!canRequest || isDisabled) {
      _invalidateAds();
      if (isDisabled) _pendingPreloads.clear();
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
    await preLoadWithResult(unit, index);
  }

  /// Like [preLoad], but reports how the load ended, so a caller can keep an
  /// accurate "ready" flag and schedule its own retry. Never throws.
  Future<AdLoadResult> preLoadWithResult(AdsUnit unit, int index) async {
    if (_adsDisabled ||
        unit == AdsUnit.banner ||
        unit == AdsUnit.native) {
      return const AdLoadResult(AdLoadOutcome.unavailable);
    }
    if (_consentMode == AdsConsentMode.managed &&
        _consentFuture != null &&
        (_consentRunning || !_eligible)) {
      // Remember the intent (bounded, one entry per slot); it runs once ads
      // become available, e.g. after the form, or after recovery of a failed
      // consent update.
      if (_pendingPreloads.length < _maxPendingPreloads) {
        _pendingPreloads.add((unit, index));
      }
      _dbg('preload ${unit.name}#$index deferred (consent not ready)');
      _requestRecovery();
      return const AdLoadResult(AdLoadOutcome.deferred);
    }
    try {
      await _load(unit, index);
    } catch (e) {
      debugPrint('Preload of ${unit.name}#$index failed: $e');
      return AdLoadResult(
        AdLoadOutcome.failed,
        errorCode: e is LoadAdError ? e.code : null,
        message: e is LoadAdError ? e.message : e.toString(),
      );
    }
    if (_cache.contains(unit, index)) {
      return const AdLoadResult(AdLoadOutcome.loaded);
    }
    return const AdLoadResult(
      AdLoadOutcome.failed,
      message: 'The load finished without a cached ad.',
    );
  }

  static const int _maxPendingPreloads = 64;

  void _dbg(String message) {
    if (kDebugMode) debugPrint('AdsManager: $message');
  }

  /// Retries a failed consent information update, at most once per
  /// [recoveryInterval], when a later request gives a safe opportunity (an ad
  /// request, a widget wanting to load, the app returning to the foreground).
  /// Does nothing unless the previous update failed and ads are unavailable.
  void _requestRecovery() {
    final params = _consentParams;
    if (_consentMode != AdsConsentMode.managed ||
        isDisabled ||
        params == null ||
        !_consentUpdateFailed ||
        _consentRunning ||
        _available.value) {
      return;
    }
    final last = _lastRecoveryAttempt;
    if (last != null && clock().difference(last) < recoveryInterval) return;
    _dbg('recovering consent state');
    _consentFuture = _runConsent(params);
  }

  /// Gives a banner / native widget that cannot load yet the chance to trigger
  /// recovery. Internal.
  @internal
  void requestRecovery() => _requestRecovery();

  void _ensureResumeObserver() {
    if (_resumeObserver != null) return;
    try {
      final observer = _LifecycleWatcher(_onLifecycleChange);
      WidgetsBinding.instance.addObserver(observer);
      _resumeObserver = observer;
    } catch (_) {
      // No binding (plain Dart tests): nothing to observe.
    }
  }

  void _onLifecycleChange(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || isDisabled || !isConfigured) {
      return;
    }
    _requestRecovery();
    if (!retryFailedAdsOnResume) return;
    final now = clock();
    final last = _lastResumeRetry;
    if (last != null && now.difference(last) < recoveryInterval) return;
    _lastResumeRetry = now;
    retryFailedAds();
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
    _dbg('load ${unit.name}#$index started');
    emit(AdEvent(type: AdEventType.request, unit: unit, index: index));

    void onLoaded(Ad ad) {
      emit(AdEvent(type: AdEventType.loaded, unit: unit, index: index));
      _attachPaid(ad, unit, index);
      if (_adsDisabled || epoch != _epoch) {
        disposeAdOnce(ad);
        _dbg('load ${unit.name}#$index finished but obsolete');
      } else {
        _cache.set(unit, index, ad);
        _dbg('load ${unit.name}#$index succeeded');
      }
      if (!completer.isCompleted) completer.complete();
    }

    void onFailed(LoadAdError error) {
      _dbg('load ${unit.name}#$index failed: code ${error.code}');
      emit(
        AdEvent(
          type: AdEventType.failed,
          unit: unit,
          index: index,
          errorCode: error.code,
          errorMessage: error.message,
        ),
      );
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

  /// Shared pipeline of the four full-screen formats.
  ///
  /// Loading and presenting are separate. Loads for different slots may run
  /// at the same time, but at most one ad is ever presented: the presentation
  /// lock is taken in one synchronous step together with the cached ad, so an
  /// ad cannot be presented twice and a stale operation cannot release a newer
  /// one. A request that finds another ad showing, or that was overtaken by
  /// another presentation while it was loading, is refused with an error and
  /// leaves its loaded ad cached; nothing is queued.
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
    final opId = ++_opCounter;
    final tag = 'op$opId ${unit.name}#$index';
    void reject(Object error) {
      _dbg('$tag rejected: $error');
      onError(error);
    }

    _dbg('$tag requested');
    if (_adsDisabled) {
      onDisabled();
      return;
    }
    _requestRecovery();
    if (!await _awaitConsent()) {
      reject(
        'Ads are not available yet: the consent flow did not finish in time.',
      );
      return;
    }
    if (_adsDisabled) {
      onDisabled();
      return;
    }
    if (_activeOp != null) {
      reject('Another full-screen ad is already loading or showing.');
      return;
    }
    if (!context.mounted) {
      reject('Context is no longer mounted.');
      return;
    }
    if (!await _awaitForeground()) {
      reject(_notForeground());
      return;
    }
    if (_adsDisabled) {
      onDisabled();
      return;
    }
    if (_activeOp != null) {
      reject('Another full-screen ad is already loading or showing.');
      return;
    }
    if (!context.mounted) {
      reject('Context is no longer mounted.');
      return;
    }
    final slot = (unit, index);
    if (_loadingShows.contains(slot)) {
      reject('Another full-screen ad is already loading or showing.');
      return;
    }

    final presentationsAtStart = _presentations;
    if (!await _requestsAllowed()) {
      _invalidateAds();
      reject('Ads cannot be requested: user consent not granted.');
      return;
    }
    if (!context.mounted) {
      reject('Context is no longer mounted.');
      return;
    }

    if (_cache.contains(unit, index)) {
      _dbg('$tag cache hit');
    } else {
      _dbg('$tag cache miss');
      _loadingShows.add(slot);
      _loadingOverlay.show(context);
      try {
        await _load(unit, index);
      } catch (e) {
        onLoadFailed?.call(e);
        reject(e);
        return;
      } finally {
        _loadingOverlay.hide();
        _loadingShows.remove(slot);
      }
      if (_cache.contains(unit, index)) onLoaded?.call();
    }

    if (_adsDisabled) {
      onDisabled();
      return;
    }
    if (!context.mounted) {
      reject('Context is no longer mounted.');
      return;
    }
    if (!await _awaitForeground()) {
      reject(_notForeground());
      return;
    }
    if (_adsDisabled) {
      onDisabled();
      return;
    }

    // From here to `present` there is no await: the check, the hand-over of
    // the cached ad and the lock are one atomic step.
    if (_activeOp != null) {
      reject('Another full-screen ad is already loading or showing.');
      return;
    }
    if (_presentations != presentationsAtStart) {
      reject(
        'Another full-screen ad was shown while this one was loading; it '
        'was not shown.',
      );
      return;
    }
    final ad = _cache.take<T>(unit, index);
    if (ad == null) {
      reject('Failed to load ${unit.name} ad');
      return;
    }

    final op = _FullScreenOp(opId);
    _activeOp = op;
    _presentations++;
    _dbg('$tag accepted');
    try {
      present(ad, op);
    } catch (e) {
      disposeAdOnce(ad);
      _releaseLock(op);
      reject(e);
    }
  }

  /// Waits (bounded by [consentWait]) for the managed start-up consent flow.
  /// Returns false if it is still running afterwards.
  Future<bool> _awaitConsent() async {
    if (_consentMode != AdsConsentMode.managed || !_consentRunning) return true;
    try {
      await consentReady.timeout(consentWait);
    } on TimeoutException {
      return false;
    }
    return !_consentRunning;
  }

  String _notForeground() {
    String? state;
    try {
      state = WidgetsBinding.instance.lifecycleState?.name;
    } catch (_) {}
    return 'The app is not in the foreground: no full-screen ad is shown'
        '${state == null ? '' : ' (lifecycle: $state)'}.';
  }

  static int _lifecycleRank(AppLifecycleState state) => switch (state) {
    AppLifecycleState.detached => -1,
    AppLifecycleState.paused => 0,
    AppLifecycleState.hidden => 1,
    AppLifecycleState.inactive => 2,
    AppLifecycleState.resumed => 3,
  };

  /// Whether the app is in the foreground. A full-screen ad is only started
  /// while the lifecycle state is `resumed`. A state on the way to `resumed`
  /// (`inactive`, `hidden`, `paused`: a system dialog, an activity such as an
  /// ad the SDK restored after the Android Activity was recreated, or the
  /// moments of a resume before Flutter reports it) is given [foregroundWait]
  /// to reach `resumed`. If the app moves further away instead, or the time
  /// runs out, the request is refused; `detached` is refused at once. This
  /// keeps an automatic ad from stacking on top of an ad that is already on
  /// screen and never shows one while the app is in the background.
  Future<bool> _awaitForeground() async {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return true;
    if (state == AppLifecycleState.detached) return false;

    var level = _lifecycleRank(state);
    final result = Completer<bool>();
    final observer = _LifecycleWatcher((next) {
      if (result.isCompleted) return;
      if (next == AppLifecycleState.resumed) {
        result.complete(true);
        return;
      }
      final rank = _lifecycleRank(next);
      if (rank < level) {
        result.complete(false);
      } else {
        level = rank;
      }
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

  /// Wires the SDK callbacks of one presented ad and shows it. Exactly one of
  /// [onDismissed] / [onFailed] runs, once. If the ad never reports that it
  /// started showing (nor dismissal nor failure) within [showStartTimeout] it
  /// is failed and the lock released; an ad that did report showing is only
  /// released by its own dismissal or failure callback.
  void _presentFullScreen<T extends Ad>({
    required T ad,
    required AdsUnit unit,
    required int index,
    required _FullScreenOp op,
    required void Function(FullScreenContentCallback<T> callback) attach,
    required Future<void> Function() show,
    void Function()? onShowed,
    required void Function() onDismissed,
    required void Function(Object error) onFailed,
  }) {
    var done = false;
    Timer? watchdog;
    void finish(void Function() notify) {
      if (done) return;
      done = true;
      watchdog?.cancel();
      _release(ad, unit, index, op);
      notify();
    }

    attach(
      FullScreenContentCallback<T>(
        onAdShowedFullScreenContent: (_) {
          watchdog?.cancel();
          if (done) return;
          _dbg('op${op.id} showed');
          emit(AdEvent(type: AdEventType.shown, unit: unit, index: index));
          onShowed?.call();
        },
        onAdImpression: (_) => _dbg('op${op.id} impression'),
        onAdDismissedFullScreenContent: (_) {
          _dbg('op${op.id} dismissed');
          finish(onDismissed);
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          _dbg('op${op.id} failed to show: $error');
          finish(() => onFailed(error));
        },
      ),
    );
    watchdog = Timer(showStartTimeout, () {
      _dbg('op${op.id} never reported showing; releasing');
      finish(
        () => onFailed(
          TimeoutException('The ad did not start showing', showStartTimeout),
        ),
      );
    });
    _runShow(show, (e) => finish(() => onFailed(e)));
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
      present: (ad, op) => _presentFullScreen(
        ad: ad,
        unit: AdsUnit.interstitial,
        index: index,
        op: op,
        attach: (cb) => ad.fullScreenContentCallback = cb,
        show: ad.show,
        onDismissed: handler.onSuccess,
        onFailed: (e) => handler.onError(e.toString()),
      ),
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
      present: (ad, op) => _presentFullScreen(
        ad: ad,
        unit: AdsUnit.appOpen,
        index: index,
        op: op,
        attach: (cb) => ad.fullScreenContentCallback = cb,
        show: ad.show,
        onDismissed: handler.onSuccess,
        onFailed: (e) => handler.onError(e.toString()),
      ),
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
        var rewarded = false;
        _presentFullScreen(
          ad: ad,
          unit: AdsUnit.rewarded,
          index: index,
          op: op,
          attach: (cb) => ad.fullScreenContentCallback = cb,
          show: () => ad.show(
            onUserEarnedReward: (_, reward) {
              if (rewarded) return;
              rewarded = true;
              handler.onRewarded?.call(reward);
            },
          ),
          onShowed: () => handler.onShowed?.call(),
          onDismissed: () => handler.onDismissed?.call(),
          onFailed: (e) => handler.onFailedToShow?.call(e),
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
        var rewarded = false;
        _presentFullScreen(
          ad: ad,
          unit: AdsUnit.rewardedInt,
          index: index,
          op: op,
          attach: (cb) => ad.fullScreenContentCallback = cb,
          show: () => ad.show(
            onUserEarnedReward: (_, reward) {
              if (rewarded) return;
              rewarded = true;
              handler.onRewarded?.call(reward);
            },
          ),
          onShowed: () => handler.onShowed?.call(),
          onDismissed: () => handler.onDismissed?.call(),
          onFailed: (e) => handler.onFailedToShow?.call(e),
        );
      },
    );
  }
}
