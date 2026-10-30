import 'dart:async';
import 'dart:typed_data';

import '../../core/cache/lru_cache.dart';
import '../api/api_client.dart';
import '../local/cover_cache.dart';
import '../local/local_store.dart';
import '../local/offline_cache.dart';
import '../models/admin_request.dart';
import '../models/entry_point.dart';
import '../models/group_filters.dart';
import '../models/rso.dart';

/// One page of search results plus how many groups match in total.
class GroupPage {
  const GroupPage(this.items, this.total);

  final List<Rso> items;
  final int total;
}

/// Student groups on the backend: Explore, profiles, saves and joins.
///
/// Most calls here are also analytics: the backend records the search, view,
/// save or join with the context sent along (entry point, source screen).
///
/// My RSOs, the unfiltered Explore page and every profile opened are kept on
/// the phone for when the backend can't be reached. Profiles opened in this
/// session are also kept in memory ([recentDetail]), so going back to one
/// shows it at once while the live copy loads.
class GroupsRepository {
  GroupsRepository(this._api, {OfflineCache? cache, CoverCache? covers})
    : _cache = cache ?? OfflineCache.disabled(),
      _covers = covers;

  final ApiClient _api;
  final OfflineCache _cache;

  /// Where the student's groups' photos are downloaded ahead of time.
  final CoverCache? _covers;

  /// A student opens a handful of groups per session, and going back to one
  /// is common (list, profile, back, another profile, back to the first). 30
  /// profiles of a few KB each cover a long session for well under 1 MB.
  final _details = LruCache<int, Rso>(capacity: 30);
  int _detailSession = -1;

  void _syncDetailSession() {
    if (_detailSession == _cache.sessionVersion) return;
    _details.clear();
    _detailSession = _cache.sessionVersion;
  }

  static const mineKey = 'groups:mine';
  static const browseKey = 'groups:browse';
  static String detailKey(int id) => 'group:$id';

  /// Explore and search. Every filter set in [filters] is logged for BQ12.
  ///
  /// Only the unfiltered, default-sorted page is kept for offline use: a
  /// search's results depend on the words typed, and offline there is nothing
  /// to search.
  Future<GroupPage> search(GroupFilters filters, {int limit = 50}) {
    Future<Object?> fetch() =>
        _api.get('/groups', query: {...filters.toQuery(), 'limit': limit});
    if (filters.isSearch || filters.sort != GroupSort.popular) {
      return fetch().then(_page);
    }
    return _cache.networkFirst(
      browseKey,
      fetch: fetch,
      parse: _page,
      save: (json) async {
        final page = json! as Map<String, dynamic>;
        await _cache.store.saveGroups('browse', page['items'] as List);
        await _cache.store.saveDocument('groups:browse:total', page['total']);
      },
      load: () async {
        final items = await _cache.store.groups('browse');
        if (items == null) return null;
        final total = await _cache.store.document('groups:browse:total');
        return Cached({
          'items': items.value,
          'total': total?.value ?? items.value.length,
        }, items.savedAt);
      },
    );
  }

  /// The full profile. Each call is logged as a view, so call it once per
  /// visit, with how the student got there.
  Future<Rso> detail(
    int id, {
    required EntryPoint entryPoint,
    String? recRequestId,
  }) async {
    _syncDetailSession();
    final session = _cache.sessionVersion;
    final rso = await _cache.networkFirst(
      detailKey(id),
      fetch: () => _api.get(
        '/groups/$id',
        query: {'entry_point': entryPoint.name, 'rec_request_id': recRequestId},
      ),
      parse: (json) => Rso.fromJson(json! as Map<String, dynamic>),
      save: (json) =>
          _cache.store.saveGroupDetail(json! as Map<String, dynamic>),
      load: () => _cache.store.groupDetail(id),
    );
    if (session == _cache.sessionVersion) _details[id] = rso;
    return rso;
  }

  /// The full profile if it was opened earlier in this session, to show while
  /// [detail] fetches the live one. Never a substitute for [detail], which is
  /// also what records the view.
  Rso? recentDetail(int id) {
    _syncDetailSession();
    return _details[id];
  }

  /// Bookmarks the group. [source] is the screen it was saved from:
  /// `explore` or `group_detail` (BQ13).
  Future<void> save(int id, {required String source}) {
    _details.remove(id);
    return _api.put('/groups/$id/save', query: {'source': source});
  }

  Future<void> unsave(int id) {
    _details.remove(id);
    return _api.delete('/groups/$id/save');
  }

  /// Submits the join form. [entryPoint] is how the profile was reached
  /// (BQ6); [joinAttemptId] is the id the form was opened with (BQ7).
  Future<void> join(
    int id, {
    required EntryPoint entryPoint,
    String? recRequestId,
    String? joinAttemptId,
    String? motivation,
  }) {
    _details.remove(id);
    return _api.post(
      '/groups/$id/join',
      body: {
        'entry_point': entryPoint.name,
        'rec_request_id': ?recRequestId,
        'join_attempt_id': ?joinAttemptId,
        'motivation': ?motivation,
      },
    );
  }

  /// Proposes a new group. It starts pending: only the student sees it, as a
  /// member, until Student Affairs approves it (platform admins then assign
  /// its group admins). Without [tagIds] the
  /// backend picks tags from the name and description.
  /// Throws [ApiException] (409 when the name is taken).
  Future<Rso> create({
    required String name,
    required String categorySlug,
    required String description,
    String? contactEmail,
    Set<int> tagIds = const {},
  }) async => Rso.fromJson(
    await _api.post(
          '/groups',
          body: {
            'name': name,
            'category': categorySlug,
            'description': description,
            'contact_email': ?contactEmail,
            if (tagIds.isNotEmpty) 'tag_ids': tagIds.toList()..sort(),
          },
        )
        as Map<String, dynamic>,
  );

  /// Uploads a new cover photo (group admins). The backend resizes it, removes
  /// its metadata (including GPS) and returns the updated group.
  Future<Rso> uploadCover(int id, Uint8List photo) async {
    _details.remove(id);
    return Rso.fromJson(
      await _api.upload(
            '/groups/$id/cover',
            field: 'file',
            bytes: photo,
            filename: 'cover.jpg',
            contentType: 'image/jpeg',
          )
          as Map<String, dynamic>,
    );
  }

  /// Asks the group's admins to make the student an admin too. Throws
  /// [ApiException] (409 when a request is already open).
  Future<void> requestAdmin(int id, {String? note}) {
    _details.remove(id);
    return _api.post('/groups/$id/admin-requests', body: {'note': ?note});
  }

  /// Open admin requests, oldest first (group admins only).
  Future<List<AdminRequest>> adminRequests(int id) async => [
    for (final item in await _api.get('/groups/$id/admin-requests') as List)
      AdminRequest.fromJson(item as Map<String, dynamic>),
  ];

  /// Approves (the member becomes admin) or declines an admin request.
  Future<void> decideAdminRequest(
    int groupId,
    int requestId, {
    required bool approve,
  }) => _api.post(
    '/groups/$groupId/admin-requests/$requestId/${approve ? 'approve' : 'reject'}',
  );

  /// Groups the student is an active member of, most recently joined first.
  ///
  /// After a live answer, their cover photos are downloaded in the background
  /// (not awaited: the list shows right away), so My RSOs has them offline.
  Future<List<Rso>> mine() async {
    final groups = await _cache.networkFirst(
      mineKey,
      fetch: () => _api.get('/me/groups'),
      parse: _list,
      save: (json) => _cache.store.saveGroups('mine', json! as List),
      load: () => _cache.store.groups('mine'),
    );
    if (_cache.freshness.cachedAt(mineKey) == null) {
      unawaited(_covers?.prefetch(groups));
    }
    return groups;
  }

  static GroupPage _page(Object? json) {
    final page = json! as Map<String, dynamic>;
    return GroupPage(_list(page['items']), page['total'] as int);
  }

  static List<Rso> _list(Object? json) => [
    for (final item in json as List) Rso.fromJson(item as Map<String, dynamic>),
  ];
}
