import 'dart:collection';

class _Kept<V> {
  _Kept(this.value, this.storedAt);

  final V value;
  final DateTime storedAt;
}

class TtlCache<K, V extends Object> {
  TtlCache({
    required this.capacity,
    required this.ttl,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       assert(capacity > 0, 'A cache needs room for at least one entry');

  final int capacity;
  final Duration ttl;
  final DateTime Function() _clock;
  final LinkedHashMap<K, _Kept<V>> _entries = LinkedHashMap();

  int _hits = 0;
  int _misses = 0;
  int _expired = 0;

  int get length => _entries.length;
  int get hits => _hits;
  int get misses => _misses;
  int get expired => _expired;

  V? operator [](K key) {
    final kept = _entries.remove(key);
    if (kept == null) {
      _misses++;
      return null;
    }
    if (_clock().difference(kept.storedAt) >= ttl) {
      _expired++;
      return null;
    }
    _hits++;
    _entries[key] = kept;
    return kept.value;
  }

  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = _Kept(value, _clock());
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  V? remove(K key) => _entries.remove(key)?.value;

  void clear() => _entries.clear();

  Iterable<K> get keys => _entries.keys;
}
