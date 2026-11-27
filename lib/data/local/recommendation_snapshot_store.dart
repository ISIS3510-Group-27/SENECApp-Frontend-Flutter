import 'dart:convert';

import '../models/recommendation.dart';
import 'local_store.dart';

/// A read-only comparison snapshot in the current account's local database.
///
/// LocalStore is opened per account and wiped at sign-out. Request IDs are
/// deliberately not persisted: a saved recommendation must not produce a
/// newly attributed view or join. The web's NoLocalStore keeps this optional.
class RecommendationSnapshotStore {
  RecommendationSnapshotStore({
    required LocalStore store,
    DateTime Function() clock = DateTime.now,
  }) : _store = store,
       _clock = clock;

  static const key = 'recommendations:comparison:v1';
  static const maxAge = Duration(hours: 24);
  static const maxItems = 10;
  static const maxBytes = 128 * 1024;

  final LocalStore _store;
  final DateTime Function() _clock;

  bool isFresh(DateTime savedAt) {
    final age = _clock().difference(savedAt);
    return !age.isNegative && age < maxAge;
  }

  Future<Cached<GroupRecommendations>?> read() async {
    try {
      final cached = await _store.document(key);
      if (cached == null || !isFresh(cached.savedAt)) return null;
      final data = cached.value! as Map<String, dynamic>;
      if (data['version'] != 1) return null;
      final items = data['items'] as List;
      if (items.length > maxItems ||
          utf8.encode(jsonEncode(data)).length > maxBytes) {
        return null;
      }
      return Cached(
        GroupRecommendations(
          requestId: '',
          modelVersion: data['model_version'] as String,
          items: List.unmodifiable([
            for (final item in items)
              GroupRecommendation.fromJson(item as Map<String, dynamic>),
          ]),
        ),
        cached.savedAt,
      );
    } on Object {
      // A corrupt, incompatible or unreadable copy is equivalent to no copy.
      return null;
    }
  }

  /// Cache failure must not replace a successful network response with error.
  Future<void> write(GroupRecommendations result) async {
    try {
      final payload = {
        'version': 1,
        'model_version': result.modelVersion,
        'items': [
          for (final item in result.items.take(maxItems))
            {
              'group': {
                'id': item.group.id,
                'name': item.group.name,
                'category': {'slug': item.group.category.slug},
                'member_count': item.group.members,
                'description': item.group.description,
                'color':
                    '#${(item.group.color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
                'verified': item.group.verified,
                'is_member': item.group.isMember,
                'image_url': _publicImage(item.group.imageUrl),
                'tags': <Object>[],
              },
              'reasons': item.reasons,
            },
        ],
      };
      if (utf8.encode(jsonEncode(payload)).length > maxBytes) return;
      // SqliteLocalStore captures the current database before yielding, so
      // a session switch cannot redirect this write to the next account.
      await _store.saveDocument(key, payload);
    } on Object {
      // Cache writes are best-effort; the live response remains usable.
    }
  }

  static String? _publicImage(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.path.isEmpty ||
        (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return value;
  }
}
