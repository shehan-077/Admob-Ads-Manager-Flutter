import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_manager.dart';
import 'ads_unit.dart';

class BannerAdContainer extends StatefulWidget {
  final int index;
  final AdSize size;

  const BannerAdContainer({
    super.key,
    required this.index,
    this.size = AdSize.banner,
  });

  @override
  State<BannerAdContainer> createState() => _BannerAdContainerState();
}

class _BannerAdContainerState extends State<BannerAdContainer> {
  BannerAd? _banner;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final id = AdsManager.instance.getAdUnitId(AdsUnit.banner, widget.index);
    final ad = BannerAd(
      adUnitId: id,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    ad.load();
    _banner = ad;
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _banner == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: _banner!.size.width.toDouble(),
      height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }
}
