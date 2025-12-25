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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final id = AdsManager.instance.getAdUnitId(AdsUnit.native, widget.index);

    final isSmall = widget.size == NativeAdsSize.small;

    final ad = NativeAd(
      adUnitId: id,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
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

    ad.load();
    _nativeAd = ad;
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
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
