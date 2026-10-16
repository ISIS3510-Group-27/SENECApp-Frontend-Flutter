import 'dart:collection';

/// A fixed-size map that forgets the least recently used entry first.
///
/// Built on a [LinkedHashMap], which keeps keys in insertion order: every read
/// or write moves the key to the end, so the first key is always the one used
/// longest ago, and the eviction is O(1) like the lookups.
///
/// Used in memory, in front of the on-disk cache, for things a student opens
/// again and again in one session (a group's or an event's full page).
class LruCache<K, V> {
  LruCache({required this.capacity})
    : assert(capacity > 0, 'An LRU cache needs room for at least one entry');

  /// The most entries kept; adding one more drops the least recently used.
  final int capacity;

  final LinkedHashMap<K, V> _entries = LinkedHashMap();

  int _hits = 0;
  int _misses = 0;

  int get length => _entries.length;

  /// Lookups that found an entry, and those that didn't. For tuning
  /// [capacity], and for explaining it.
  int get hits => _hits;
  int get misses => _misses;

  /// The value for [key], marking it as the most recently used; `null` if it
  /// isn't cached.
  V? operator [](K key) {
    final value = _entries.remove(key);
    if (value == null) {
      _misses++;
      return null;
    }
    _hits++;
    _entries[key] = value;
    return value;
  }

  /// Stores [value] as the most recently used entry, evicting the least
  /// recently used one when the cache is full.
  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  bool containsKey(K key) => _entries.containsKey(key);

  V? remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();

  /// Keys from least to most recently used.
  Iterable<K> get keys => _entries.keys;
}
