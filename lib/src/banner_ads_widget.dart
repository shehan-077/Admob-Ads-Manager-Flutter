import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_manager.dart';
import 'ads_unit.dart';

class BannerAdContainer extends StatefulWidget {
  final int index;

  const BannerAdContainer({super.key, required this.index});

  @override
  State<BannerAdContainer> createState() => _BannerAdContainerState();
}

class _BannerAdContainerState extends State<BannerAdContainer> {
  BannerAd? _banner;
  bool _isLoaded = false;
  AdSize? _adSize;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_banner == null && !_isLoading) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant BannerAdContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _disposeAd();
      _load();
    }
  }

  Future<void> _load() async {
    if (_isLoading) return;
    if (AdsManager.instance.isDisabled) return;
    _isLoading = true;

    final width = MediaQuery.sizeOf(context).width.truncate();

    final AdSize? adaptiveSize = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);

    if (!mounted) return;

    if (adaptiveSize == null) {
      debugPrint('Unable to get adaptive banner ad size');
      _isLoaded = false;
      return;
    }

    _adSize = adaptiveSize;

    final id = AdsManager.instance.getAdUnitId(AdsUnit.banner, widget.index);

    final ad = BannerAd(
      adUnitId: id,
      size: adaptiveSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }

          setState(() {
            _banner = ad as BannerAd;
            _isLoaded = true;
            _isLoading = false;
          });

        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed to load: $error');
          ad.dispose();
          if (!mounted) return;

          setState(() {
            _banner = null;
            _isLoaded = false;
            _isLoading = false;
          });
        },
      ),
    );

    ad.load();
  }

  void _disposeAd() {
    _banner?.dispose();
    _banner = null;
    _adSize = null;
    _isLoaded = false;
    _isLoading = false;
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AdsManager.instance.isDisabled) return const SizedBox.shrink();
    if (!_isLoaded || _banner == null || _adSize == null) return const SizedBox.shrink();

    return SizedBox(
      width: _adSize!.width.toDouble(),
      height: _adSize!.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }
}
