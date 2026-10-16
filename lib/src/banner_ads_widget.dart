import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_manager.dart';
import 'ads_unit.dart';
import 'banner_config.dart';
import 'banner_types.dart';

/// Banner ad widget.
///
/// The ad is requested only when ads are available (see
/// [AdsManager.adsAvailable]) and again only when the index, type, size,
/// placement, max height, available width or orientation change. A failed load
/// is retried only through [AdsManager.retryFailedAds].
class BannerAdContainer extends StatefulWidget {
  /// Ad unit slot; indexes beyond the configured list wrap around.
  final int index;

  /// Banner flavour. Defaults to [BannerAdsType.normal].
  final BannerAdsType type;

  /// Size used by [BannerAdsType.fixed]; ignored by the other types.
  final BannerAdsSize size;

  /// Edge used by [BannerAdsType.collapsible]. The widget must really be
  /// placed at this edge of the screen.
  final BannerCollapsiblePlacement collapsiblePlacement;

  /// Upper bound in dp for [BannerAdsType.inlineAdaptive].
  final double? maxHeight;

  /// Request configuration; collapsible parameters are merged into it.
  final AdRequest? request;

  const BannerAdContainer({
    super.key,
    required this.index,
    this.type = BannerAdsType.normal,
    this.size = BannerAdsSize.banner,
    this.collapsiblePlacement = BannerCollapsiblePlacement.bottom,
    this.maxHeight,
    this.request,
  });

  @override
  State<BannerAdContainer> createState() => _BannerAdContainerState();
}

typedef _Key = ({
  int index,
  BannerAdsType type,
  BannerAdsSize size,
  BannerCollapsiblePlacement placement,
  int? maxHeight,
  int width,
  Orientation orientation,
  bool fits,
});

class _BannerAdContainerState extends State<BannerAdContainer> {
  final AdsManager _manager = AdsManager.instance;

  BannerAd? _banner;
  AdSize? _displaySize;

  _Key? _requestedKey;
  _Key? _pendingKey;
  _Key? _scheduledKey;
  _Key? _loggedKey;

  int _generation = 0;
  bool _loading = false;
  bool _failed = false;

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
    final banner = _banner;
    _banner = null;
    if (banner != null) disposeAdOnce(banner);
    super.dispose();
  }

  void _onAvailabilityChanged() {
    if (!mounted) return;
    if (!_manager.adsAvailable.value) {
      _retireCurrent();
      _requestedKey = null;
    } else {
      final key = _pendingKey;
      if (key != null) _maybeStart(key);
    }
  }

  void _onRetryRequested() {
    final request = _manager.retryRequests.value;
    if (!mounted || request == null) return;
    if (!request.matches(AdsUnit.banner, widget.index)) return;
    if (!_failed || _loading) return;
    if (_manager.isDisabled || !_manager.adsAvailable.value) return;
    final key = _pendingKey;
    if (key == null) return;
    _requestedKey = null;
    _maybeStart(key);
  }

  void _retireCurrent() {
    _generation++;
    _loading = false;
    _failed = false;
    final old = _banner;
    if (old == null && _displaySize == null) return;
    setState(() {
      _banner = null;
      _displaySize = null;
    });
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => disposeAdOnce(old));
    }
  }

  void _schedule(_Key key) {
    _pendingKey = key;
    if (key == _requestedKey || key == _scheduledKey) return;
    _scheduledKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduledKey = null;
      if (!mounted) return;
      final pending = _pendingKey;
      if (pending != null) _maybeStart(pending);
    });
  }

  void _maybeStart(_Key key) {
    if (key == _requestedKey) return;
    if (_manager.isDisabled || !_manager.adsAvailable.value) return;

    _retireCurrent();
    _requestedKey = key;

    if (!key.fits) {
      if (_loggedKey != key) {
        _loggedKey = key;
        final adSize = widget.size.adSize;
        debugPrint(
          'BannerAdContainer: the ${widget.size.name} fixed banner '
          '(${adSize.width}x${adSize.height}) does not fit the available '
          'space and was not loaded. '
          '${widget.size.tabletOnly ? 'This size is meant for tablets. ' : ''}'
          'Ads are never scaled, cropped or stretched.',
        );
      }
      return;
    }
    unawaited(_load(key, _generation));
  }

  void _finish(int generation, {required bool failed}) {
    if (generation != _generation) return;
    _loading = false;
    _failed = failed;
  }

  Future<void> _load(_Key key, int generation) async {
    _loading = true;
    _failed = false;
    try {
      final id = _manager.getBannerAdUnitId(key.index, type: key.type);

      final AdSize adSize;
      switch (key.type) {
        case BannerAdsType.normal:
        case BannerAdsType.collapsible:
          final anchored = await _manager.sdk.anchoredAdaptiveSize(
            key.orientation,
            key.width,
          );
          if (!mounted || generation != _generation) return;
          if (anchored == null) {
            debugPrint('Unable to get adaptive banner ad size');
            _finish(generation, failed: true);
            return;
          }
          adSize = anchored;
        case BannerAdsType.inlineAdaptive:
          final maxHeight = key.maxHeight;
          adSize = maxHeight != null
              ? AdSize.getInlineAdaptiveBannerAdSize(key.width, maxHeight)
              : AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(
                  key.width,
                );
        case BannerAdsType.fixed:
          adSize = key.size.adSize;
      }

      final request = buildBannerRequest(
        widget.request,
        key.type,
        key.placement,
      );

      final banner = _manager.sdk.createBanner(
        id,
        adSize,
        request,
        BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || generation != _generation) {
              disposeAdOnce(ad);
              return;
            }
            if (key.type == BannerAdsType.inlineAdaptive) {
              unawaited(_finishInline(ad as BannerAd, generation));
            } else {
              _show(ad as BannerAd, adSize, generation);
            }
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('Banner failed to load: $error');
            disposeAdOnce(ad);
            _finish(generation, failed: true);
          },
        ),
      );
      try {
        await banner.load();
      } catch (e) {
        debugPrint('Banner request failed: $e');
        disposeAdOnce(banner);
        _finish(generation, failed: true);
      }
    } catch (e) {
      debugPrint('Banner request failed: $e');
      _finish(generation, failed: true);
    }
  }

  Future<void> _finishInline(BannerAd ad, int generation) async {
    AdSize? platformSize;
    try {
      platformSize = await ad.getPlatformAdSize();
    } catch (e) {
      debugPrint('Unable to read inline banner size: $e');
    }
    if (!mounted || generation != _generation) {
      disposeAdOnce(ad);
      return;
    }
    if (platformSize == null || platformSize.height <= 0) {
      disposeAdOnce(ad);
      _finish(generation, failed: true);
      return;
    }
    _show(ad, platformSize, generation);
  }

  void _show(BannerAd ad, AdSize size, int generation) {
    _finish(generation, failed: false);
    setState(() {
      _banner = ad;
      _displaySize = size;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_manager.isDisabled) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final width = resolveBannerWidth(
          maxWidth: constraints.maxWidth,
          screenWidth: media.size.width,
          horizontalInset: media.padding.horizontal,
        );
        final fits =
            widget.type != BannerAdsType.fixed ||
            fixedBannerFits(widget.size.adSize, constraints);

        _schedule((
          index: widget.index,
          type: widget.type,
          size: widget.size,
          placement: widget.collapsiblePlacement,
          maxHeight: widget.maxHeight?.truncate(),
          width: width,
          orientation: media.orientation,
          fits: fits,
        ));

        final banner = _banner;
        final size = _displaySize;
        if (banner == null || size == null) return const SizedBox.shrink();

        return Align(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: KeyedSubtree(
              key: ObjectKey(banner),
              child: _manager.sdk.adWidget(banner),
            ),
          ),
        );
      },
    );
  }
}
