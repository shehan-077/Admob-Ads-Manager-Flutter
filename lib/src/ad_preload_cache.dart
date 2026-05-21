import 'ads_unit.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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

class AdPreloadCache {
  final Map<_AdKey, Ad> _cache = {};

  T? get<T extends Ad>(AdsUnit unit, int index) {
    final obj = _cache[_AdKey(unit, index)];
    return obj is T ? obj : null;
  }

  void set(AdsUnit unit, int index, Ad ad) {
    final key = _AdKey(unit, index);
    _cache[key]?.dispose();
    _cache[key] = ad;
  }

  bool contains(AdsUnit unit, int index) {
    return _cache.containsKey(_AdKey(unit, index));
  }

  T? remove<T extends Ad>(AdsUnit unit, int index) {
    final ad = _cache.remove(_AdKey(unit, index));
    ad?.dispose();
  }

  void clear() {
    for (final ad in _cache.values) {
      ad.dispose();
    }
    _cache.clear();
  }
}
