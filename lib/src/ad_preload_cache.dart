import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_unit.dart';

class _AdKey {
  final AdsUnit unit;
  final int index;

  const _AdKey(this.unit, this.index);

  @override
  bool operator ==(Object other) =>
      other is _AdKey && unit == other.unit && index == other.index;

  @override
  int get hashCode => Object.hash(unit, index);
}

class _Entry {
  final Ad ad;
  final DateTime loadedAt;

  _Entry(this.ad, this.loadedAt);
}

/// Cache of preloaded full-screen ads.
///
/// Ads expire: Google documents 1 hour for interstitial / rewarded /
/// rewarded interstitial ads and 4 hours for app open ads. Expired ads are
/// disposed and never returned.
class AdPreloadCache {
  static const Duration defaultExpiry = Duration(hours: 1);
  static const Duration appOpenExpiry = Duration(hours: 4);

  final Map<_AdKey, _Entry> _cache = {};
  final DateTime Function() _now;

  AdPreloadCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static Duration expiryFor(AdsUnit unit) =>
      unit == AdsUnit.appOpen ? appOpenExpiry : defaultExpiry;

  bool _isExpired(AdsUnit unit, _Entry entry) =>
      _now().difference(entry.loadedAt) >= expiryFor(unit);

  /// Returns the cached ad without removing it, or null if there is none or
  /// it has expired (an expired ad is disposed and evicted).
  T? get<T extends Ad>(AdsUnit unit, int index) {
    final key = _AdKey(unit, index);
    final entry = _cache[key];
    if (entry == null) return null;
    if (_isExpired(unit, entry)) {
      _cache.remove(key);
      entry.ad.dispose();
      return null;
    }
    final ad = entry.ad;
    return ad is T ? ad : null;
  }

  /// Removes and returns the cached ad **without disposing it**, handing
  /// ownership to the caller. Returns null if there is none or it expired.
  T? take<T extends Ad>(AdsUnit unit, int index) {
    final ad = get<T>(unit, index);
    if (ad != null) _cache.remove(_AdKey(unit, index));
    return ad;
  }

  /// Stores [ad]. A different ad previously stored under the same key is
  /// disposed.
  void set(AdsUnit unit, int index, Ad ad) {
    final key = _AdKey(unit, index);
    final previous = _cache[key]?.ad;
    if (previous != null && !identical(previous, ad)) previous.dispose();
    _cache[key] = _Entry(ad, _now());
  }

  bool contains(AdsUnit unit, int index) => get<Ad>(unit, index) != null;

  /// Removes and disposes the cached ad, if any.
  void remove(AdsUnit unit, int index) {
    _cache.remove(_AdKey(unit, index))?.ad.dispose();
  }

  void clear() {
    for (final entry in _cache.values) {
      entry.ad.dispose();
    }
    _cache.clear();
  }
}
