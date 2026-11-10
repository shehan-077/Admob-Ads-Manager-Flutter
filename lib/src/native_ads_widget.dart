import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_events.dart';
import 'ads_manager.dart';
import 'ads_unit.dart';
import 'banner_config.dart';

/// Native ad rendered with one of Google's native templates.
///
/// The ad is requested when ads are available and again when [index], [size]
/// or the template that applies to the available width change. A failed load
/// is retried only through [AdsManager.retryFailedAds].
class NativeAdsContainer extends StatefulWidget {
  /// Ad unit slot; indexes beyond the configured list wrap around.
  final int index;

  /// Template size.
  final NativeAdsSize size;

  /// Optional container height in dp. Clamped to Google's documented template
  /// range (small 90-200, medium 320-400). Defaults to 120 (small) and, for
  /// medium, 0.92 x the available width within 320-400.
  final double? height;

  /// Optional maximum width in dp (Google recommends at most 400). By default
  /// the ad uses the available width.
  final double? maxWidth;

  /// On iOS, [NativeAdsSize.small] uses the medium template when the available
  /// width is below 480 points. Google's iOS small template limits its media
  /// area to a quarter of its width, so a video could never reach the 120x120
  /// point minimum required for a MediaView that shows video. Set this to false
  /// to keep the compact template anyway (the AdMob native ad validator then
  /// reports "MediaView is too small for video" for video creatives).
  final bool iosSmallMediaFallback;

  const NativeAdsContainer({
    super.key,
    required this.index,
    required this.size,
    this.height,
    this.maxWidth,
    this.iosSmallMediaFallback = true,
  });

  @override
  State<NativeAdsContainer> createState() => _NativeAdsContainerState();
}

typedef _NativeKey = ({int index, NativeAdsSize template});

class _NativeAdsContainerState extends State<NativeAdsContainer> {
  final AdsManager _manager = AdsManager.instance;

  NativeAd? _nativeAd;
  _NativeKey? _requestedKey;
  _NativeKey? _pendingKey;
  _NativeKey? _scheduledKey;
  NativeAdsSize? _loadedTemplate;
  int _generation = 0;
  bool _loading = false;
  bool _failed = false;

  Timer? _autoRetryTimer;
  int _autoAttempt = 0;

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
  }

  void _scheduleAutoRetry() {
    final delays = _manager.autoRetryBackoff;
    if (_autoAttempt >= delays.length) return;
    final delay = delays[_autoAttempt++];
    _cancelAutoRetry();
    _autoRetryTimer = Timer(delay, () {
      _autoRetryTimer = null;
      if (!mounted) return;
      _retryFailed();
    });
  }

  @override
  void initState() {
    super.initState();
    _manager.adsAvailable.addListener(_onAvailabilityChanged);
    _manager.retryRequests.addListener(_onRetryRequested);
  }

  @override
  void dispose() {
    _manager.adsAvailable.removeListener(_onAvailabilityChanged);
    _manager.retryRequests.removeListener(_onRetryRequested);
    _generation++;
    _cancelAutoRetry();
    final ad = _nativeAd;
    _nativeAd = null;
    if (ad != null) disposeAdOnce(ad);
    super.dispose();
  }

  void _onAvailabilityChanged() {
    if (!mounted) return;
    if (_manager.adsAvailable.value) {
      final key = _pendingKey;
      if (key != null) _start(key);
    } else {
      _retire();
      _requestedKey = null;
    }
  }

  void _onRetryRequested() {
    final request = _manager.retryRequests.value;
    if (!mounted || request == null) return;
    if (!request.matches(AdsUnit.native, widget.index)) return;
    if (!_failed || _loading) return;
    _autoAttempt = 0; // an explicit retry restarts the automatic schedule
    _retryFailed();
  }

  void _retryFailed() {
    if (!_failed || _loading) return;
    if (_manager.isDisabled || !_manager.adsAvailable.value) return;
    final key = _pendingKey;
    if (key == null) return;
    _cancelAutoRetry();
    _requestedKey = null;
    _start(key);
  }

  void _retire() {
    _generation++;
    _cancelAutoRetry();
    _loading = false;
    _failed = false;
    final old = _nativeAd;
    if (old == null) return;
    setState(() {
      _nativeAd = null;
      _loadedTemplate = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => disposeAdOnce(old));
  }

  void _schedule(_NativeKey key) {
    _pendingKey = key;
    if (key == _requestedKey || key == _scheduledKey) return;
    _scheduledKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduledKey = null;
      if (!mounted) return;
      final pending = _pendingKey;
      if (pending != null) _start(pending);
    });
  }

  void _finish(int generation, {required bool failed}) {
    if (generation != _generation) return;
    _loading = false;
    _failed = failed;
    if (failed) {
      _scheduleAutoRetry();
    } else {
      _autoAttempt = 0;
    }
  }

  AdEvent _event(AdEventType type, {int? code, String? message}) => AdEvent(
    type: type,
    unit: AdsUnit.native,
    index: widget.index,
    errorCode: code,
    errorMessage: message,
  );

  void _start(_NativeKey key) {
    if (key == _requestedKey) return;
    if (_manager.isDisabled) return;
    if (!_manager.adsAvailable.value) {
      _manager.requestRecovery();
      return;
    }
    _retire();
    _requestedKey = key;
    final generation = _generation;
    _loading = true;
    _failed = false;

    try {
      final id = _manager.getAdUnitId(AdsUnit.native, key.index);
      final isSmall = key.template == NativeAdsSize.small;

      final ad = _manager.sdk.createNative(
        id,
        NativeAdListener(
          onAdImpression: (_) => _manager.emit(_event(AdEventType.shown)),
          onPaidEvent: (_, micros, precision, currency) => _manager.emit(
            AdEvent(
              type: AdEventType.paid,
              unit: AdsUnit.native,
              index: widget.index,
              valueMicros: micros,
              currencyCode: currency,
              precision: precision.name,
            ),
          ),
          onAdLoaded: (ad) {
            _manager.emit(_event(AdEventType.loaded));
            if (!mounted || generation != _generation) {
              disposeAdOnce(ad);
              return;
            }
            _finish(generation, failed: false);
            setState(() {
              _nativeAd = ad as NativeAd;
              _loadedTemplate = key.template;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('Native failed: $error');
            _manager.emit(
              _event(
                AdEventType.failed,
                code: error.code,
                message: error.message,
              ),
            );
            disposeAdOnce(ad);
            _finish(generation, failed: true);
          },
        ),
        NativeTemplateStyle(
          templateType: isSmall ? TemplateType.small : TemplateType.medium,
        ),
        NativeAdOptions(
          mediaAspectRatio: MediaAspectRatio.landscape,
          shouldRequestMultipleImages: true,
          videoOptions: isSmall
              ? null
              : VideoOptions(
                  startMuted: true,
                  clickToExpandRequested: true,
                  customControlsRequested: true,
                ),
        ),
      );
      _manager.emit(_event(AdEventType.request));
      unawaited(
        ad.load().catchError((Object e) {
          debugPrint('Native request failed: $e');
          disposeAdOnce(ad);
          _finish(generation, failed: true);
        }),
      );
    } catch (e) {
      debugPrint('Native request failed: $e');
      _finish(generation, failed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_manager.isDisabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = widget.maxWidth;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final constrained = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screenWidth;
        final available = maxWidth == null
            ? constrained
            : math.min(constrained, maxWidth);

        final template = effectiveNativeSize(
          widget.size,
          availableWidth: available,
          iosSmallMediaFallback: widget.iosSmallMediaFallback,
        );
        _schedule((index: widget.index, template: template));

        final ad = _nativeAd;
        if (ad == null) return const SizedBox.shrink();

        return Align(
          heightFactor: 1,
          child: SizedBox(
            width: maxWidth ?? double.infinity,
            height: resolveNativeHeight(
              _loadedTemplate ?? template,
              template == widget.size ? widget.height : null,
              availableWidth: available,
            ),
            child: KeyedSubtree(
              key: ObjectKey(ad),
              child: _manager.sdk.adWidget(ad),
            ),
          ),
        );
      },
    );
  }
}
