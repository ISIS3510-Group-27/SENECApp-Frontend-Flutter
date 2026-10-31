import 'dart:collection';

/// A fixed-size map that forgets the least recently used entry first, and
/// optionally any entry older than [maxAge].
///
/// Built on a [LinkedHashMap], which keeps keys in insertion order: every read
/// or write moves the key to the end, so the first key is always the one used
/// longest ago, and the eviction is O(1) like the lookups.
///
/// Two independent limits:
/// - **size** ([capacity]): bounds memory. Adding one entry too many drops the
///   least recently used one.
/// - **expiration** ([maxAge]): bounds how old a value can be. Each entry
///   remembers when it was stored; a read after [maxAge] drops it and counts
///   as [expired], so the caller fetches a fresh one. Expired entries are
///   removed when read (lazily), with no timer running in the background.
///
/// Used in memory, in front of the on-disk cache, for things a student opens
/// again and again in one session (a group's or an event's full page).
class LruCache<K, V> {
  LruCache({required this.capacity, this.maxAge, DateTime Function()? clock})
    : assert(capacity > 0, 'An LRU cache needs room for at least one entry'),
      assert(
        maxAge == null || maxAge > Duration.zero,
        'An expiration must be longer than zero',
      ),
      _clock = clock ?? DateTime.now;

  /// The most entries kept; adding one more drops the least recently used.
  final int capacity;

  /// How long an entry stays valid after it's stored; `null` for no
  /// expiration (only [capacity] applies).
  final Duration? maxAge;

  final DateTime Function() _clock;

  final LinkedHashMap<K, _Entry<V>> _entries = LinkedHashMap();

  int _hits = 0;
  int _misses = 0;
  int _expired = 0;

  int get length => _entries.length;

  /// Lookups that found a valid entry, that found nothing, and that found an
  /// entry too old to use. For tuning [capacity] and [maxAge], and for
  /// explaining them.
  int get hits => _hits;
  int get misses => _misses;
  int get expired => _expired;

  /// The value for [key], marking it as the most recently used; `null` if it
  /// isn't cached or is older than [maxAge].
  V? operator [](K key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      _misses++;
      return null;
    }
    if (_isExpired(entry)) {
      _expired++;
      return null;
    }
    _hits++;
    _entries[key] = entry;
    return entry.value;
  }

  /// Stores [value] as the most recently used entry (restarting its age),
  /// evicting the least recently used one when the cache is full.
  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = _Entry(value, _clock());
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  /// Whether a valid (not expired) entry is stored, without counting a lookup
  /// or changing the order.
  bool containsKey(K key) {
    final entry = _entries[key];
    return entry != null && !_isExpired(entry);
  }

  V? remove(K key) => _entries.remove(key)?.value;

  void clear() => _entries.clear();

  /// Keys from least to most recently used.
  Iterable<K> get keys => _entries.keys;

  bool _isExpired(_Entry<V> entry) {
    final maxAge = this.maxAge;
    return maxAge != null && _clock().difference(entry.storedAt) >= maxAge;
  }
}

/// A value and when it was stored.
class _Entry<V> {
  _Entry(this.value, this.storedAt);

  final V value;
  final DateTime storedAt;
}
