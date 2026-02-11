import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_manager.dart';
import 'ads_unit.dart';

class NativeAdsContainer extends StatefulWidget {
  final int index;
  final NativeAdsSize size;

  const NativeAdsContainer({
    super.key,
    required this.index,
    required this.size,
  });

  @override
  State<NativeAdsContainer> createState() => _NativeAdsContainerState();
}

class _NativeAdsContainerState extends State<NativeAdsContainer> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NativeAdsContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index || oldWidget.size != widget.size) {
      _disposeAd();
      _load();
    }
  }

  void _disposeAd() {
    _nativeAd?.dispose();
    _nativeAd = null;
    _isLoaded = false;
    _isLoading = false;
  }

  void _load() {
    if (_isLoading) return;
    _isLoading = true;

    final id = AdsManager.instance.getAdUnitId(AdsUnit.native, widget.index);
    final isSmall = widget.size == NativeAdsSize.small;

    final ad = NativeAd(
      adUnitId: id,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Native failed: $error');
          ad.dispose();
          if (!mounted) return;
          setState(() {
            // ensure we don't keep a disposed ad
            if (_nativeAd == ad) _nativeAd = null;
            _isLoaded = false;
          });
          _isLoading = false;
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: isSmall ? TemplateType.small : TemplateType.medium,
      ),
      nativeAdOptions: NativeAdOptions(
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

    setState(() {
      _nativeAd = ad;
      _isLoaded = false;
    });

    ad.load();
    _isLoading = false;
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) return const SizedBox.shrink();

    final height = widget.size == NativeAdsSize.small ? 140.0 : 360.0;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
