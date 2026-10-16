import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_unit.dart';
import 'banner_types.dart';

/// Builds the request for a banner, preserving everything configured on
/// [base] and adding the documented `collapsible` extra when needed.
AdRequest buildBannerRequest(
  AdRequest? base,
  BannerAdsType type,
  BannerCollapsiblePlacement placement,
) {
  final request = base ?? const AdRequest();
  if (type != BannerAdsType.collapsible) return request;

  return AdRequest(
    keywords: request.keywords,
    contentUrl: request.contentUrl,
    neighboringContentUrls: request.neighboringContentUrls,
    nonPersonalizedAds: request.nonPersonalizedAds,
    httpTimeoutMillis: request.httpTimeoutMillis,
    // ignore: deprecated_member_use
    mediationExtrasIdentifier: request.mediationExtrasIdentifier,
    mediationExtras: request.mediationExtras,
    extras: <String, String>{...?request.extras, 'collapsible': placement.name},
  );
}

/// Width (dp) available to an adaptive banner.
///
/// [maxWidth] comes from the layout constraints (which already exclude parent
/// padding). When the widget spans the whole screen width, the remaining
/// horizontal safe-area insets are removed as well. Unbounded constraints fall
/// back to the screen width.
int resolveBannerWidth({
  required double maxWidth,
  required double screenWidth,
  required double horizontalInset,
}) {
  var width = maxWidth.isFinite ? maxWidth : screenWidth;
  if (width >= screenWidth - 0.5) width -= horizontalInset;
  return width.isFinite && width > 0 ? width.floor() : 0;
}

/// Whether a fixed-size banner fits the layout constraints. The ad is never
/// scaled, cropped or stretched, so it is simply not loaded when it does not
/// fit.
bool fixedBannerFits(AdSize size, BoxConstraints constraints) {
  if (constraints.maxWidth.isFinite && constraints.maxWidth < size.width) {
    return false;
  }
  if (constraints.maxHeight.isFinite && constraints.maxHeight < size.height) {
    return false;
  }
  return true;
}

final Expando<bool> _disposed = Expando<bool>('adDisposed');

/// Disposes [ad] at most once, swallowing platform errors.
void disposeAdOnce(Ad ad) {
  if (_disposed[ad] == true) return;
  _disposed[ad] = true;
  try {
    ad.dispose().catchError((Object _) {});
  } catch (e) {
    debugPrint('Ad dispose failed: $e');
  }
}

/// Height of a native template container.
///
/// A requested height is clamped to Google's documented template range:
/// 90-200 for small, 320-400 for medium. Without a request, small is 120 and
/// medium grows with [availableWidth] (0.92 x width, within 320-400) because
/// the template's media view gets taller on wider screens; a fixed 320 clipped
/// the call-to-action on a 392 dp wide phone.
double resolveNativeHeight(
  NativeAdsSize size,
  double? requested, {
  double? availableWidth,
}) {
  final small = size == NativeAdsSize.small;
  final min = small ? 90.0 : 320.0;
  final max = small ? 200.0 : 400.0;
  var fallback = small ? 120.0 : 320.0;
  final width = availableWidth;
  if (!small && width != null && width.isFinite) {
    fallback = (width * 0.92).clamp(min, max).toDouble();
  }
  final value = requested ?? fallback;
  if (value.isNaN) return fallback;
  return value.clamp(min, max).toDouble();
}

/// Smallest width (points) at which the iOS small template can show a video
/// MediaView of 120x120: its media area is limited to a quarter of the width.
const double iosSmallTemplateMinVideoWidth = 480;

/// The template actually used for [size].
///
/// Google's iOS small template limits its media area to 25% of its width, so
/// below [iosSmallTemplateMinVideoWidth] a video cannot reach the 120x120 point
/// minimum that the AdMob native ad validator and policy require, whatever the
/// container height. With [iosSmallMediaFallback] the medium template (full
/// width media) is used instead on iOS. Android's small template has no media
/// view and is unaffected.
NativeAdsSize effectiveNativeSize(
  NativeAdsSize size, {
  required double availableWidth,
  required bool iosSmallMediaFallback,
  TargetPlatform? platform,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (size == NativeAdsSize.small &&
      iosSmallMediaFallback &&
      target == TargetPlatform.iOS &&
      availableWidth < iosSmallTemplateMinVideoWidth) {
    return NativeAdsSize.medium;
  }
  return size;
}
