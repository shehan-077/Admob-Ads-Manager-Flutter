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
      _banner?.dispose();
      _banner = null;
      _isLoaded = false;
      _adSize = null;
      _isLoading = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (_isLoading) return;
    if (AdsManager.instance.isDisabled) return;
    _isLoading = true;

    final size = MediaQuery.sizeOf(context);
    final adSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
          size.width.truncate(),
        );

    if (!mounted) return;

    _adSize = adSize ?? AdSize.banner;

    final id = AdsManager.instance.getAdUnitId(AdsUnit.banner, widget.index);

    final ad = BannerAd(
      adUnitId: id,
      size: _adSize!,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed to load: $error');
          ad.dispose();
        },
      ),
    );

    await ad.load();
    if (!mounted) return;

    setState(() {
      _banner = ad;
    });

    _isLoading = false;
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AdsManager.instance.isDisabled) return const SizedBox.shrink();
    if (!_isLoaded || _banner == null || _adSize == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: _adSize!.height.toDouble(),
      child: Align(
        alignment: Alignment.center,
        child: AdWidget(ad: _banner!),
      ),
    );
  }
}
