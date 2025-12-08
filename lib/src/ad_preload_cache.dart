import 'ads_unit.dart';

class _AdKey {
  final AdsUnit unit;
  final int index;

  const _AdKey(this.unit, this.index);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AdKey &&
          runtimeType == other.runtimeType &&
          unit == other.unit &&
          index == other.index;

  @override
  int get hashCode => unit.hashCode ^ index.hashCode;
}

class AdPreloadCache {
  final Map<_AdKey, Object> _cache = {};

  T? get<T>(AdsUnit unit, int index) {
    final obj = _cache[_AdKey(unit, index)];
    if (obj is T) return obj;
    return null;
  }

  void set(AdsUnit unit, int index, Object ad) {
    _cache[_AdKey(unit, index)] = ad;
  }

  void remove(AdsUnit unit, int index) {
    _cache.remove(_AdKey(unit, index));
  }

  void clear() => _cache.clear();
}
