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

class AdPreloadCache {
  final Map<_AdKey, Object> _cache = {};

  T? get<T>(AdsUnit unit, int index) {
    final obj = _cache[_AdKey(unit, index)];
    return obj is T ? obj : null;
  }

  void set(AdsUnit unit, int index, Object ad) {
    _cache[_AdKey(unit, index)] = ad;
  }

  bool contains(AdsUnit unit, int index) =>
      _cache.containsKey(_AdKey(unit, index));

  void remove(AdsUnit unit, int index) {
    _cache.remove(_AdKey(unit, index));
  }

  void clear() => _cache.clear();
}
