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
    this.size = NativeAdsSize.small,
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
    final ad = NativeAd(
      adUnitId: id,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.size == NativeAdsSize.small
            ? TemplateType.small
            : TemplateType.medium,
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
    if (!_isLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    // Determine height based on template type
    // Small template is typically around 90-100dp
    // Medium template is typically around 300-350dp
    double height = widget.size == NativeAdsSize.small ? 90.0 : 350.0;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
