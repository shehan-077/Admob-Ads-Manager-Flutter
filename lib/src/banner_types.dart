import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner flavour rendered by `BannerAdContainer`.
enum BannerAdsType {
  /// Anchored adaptive banner (default).
  normal,

  /// Anchored adaptive banner that can expand over the app content. Place the
  /// widget at the screen edge given by `collapsiblePlacement`.
  collapsible,

  /// Inline adaptive banner for scrolling content; its height is decided by
  /// the SDK after loading.
  inlineAdaptive,

  /// One of the fixed [BannerAdsSize] banners.
  fixed,
}

/// Fixed banner sizes (see the AdMob "Fixed size banners" guide).
enum BannerAdsSize {
  /// 320x50, phones and tablets.
  banner,

  /// 320x100, phones and tablets.
  largeBanner,

  /// 300x250, phones and tablets.
  mediumRectangle,

  /// 468x60, tablets only.
  fullBanner,

  /// 728x90, tablets only.
  leaderboard;

  /// The SDK size for this value.
  AdSize get adSize {
    switch (this) {
      case BannerAdsSize.banner:
        return AdSize.banner;
      case BannerAdsSize.largeBanner:
        return AdSize.largeBanner;
      case BannerAdsSize.mediumRectangle:
        return AdSize.mediumRectangle;
      case BannerAdsSize.fullBanner:
        return AdSize.fullBanner;
      case BannerAdsSize.leaderboard:
        return AdSize.leaderboard;
    }
  }

  /// Sizes Google documents as tablet-only.
  bool get tabletOnly =>
      this == BannerAdsSize.fullBanner || this == BannerAdsSize.leaderboard;
}

/// Edge of the screen the collapsible banner is anchored to. The widget must
/// actually be placed at that edge.
enum BannerCollapsiblePlacement { bottom, top }
