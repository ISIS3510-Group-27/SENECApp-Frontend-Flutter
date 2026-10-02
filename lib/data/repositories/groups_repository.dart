import '../api/api_client.dart';
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
class GroupsRepository {
  const GroupsRepository(this._api);

  final ApiClient _api;

  /// Explore and search. Every filter set in [filters] is logged for BQ12.
  Future<GroupPage> search(GroupFilters filters, {int limit = 50}) async {
    final json =
        await _api.get('/groups', query: {...filters.toQuery(), 'limit': limit})
            as Map<String, dynamic>;
    return GroupPage(_list(json['items']), json['total'] as int);
  }

  /// The full profile. Each call is logged as a view, so call it once per
  /// visit, with how the student got there.
  Future<Rso> detail(
    int id, {
    required EntryPoint entryPoint,
    String? recRequestId,
  }) async => Rso.fromJson(
    await _api.get(
          '/groups/$id',
          query: {
            'entry_point': entryPoint.name,
            'rec_request_id': recRequestId,
          },
        )
        as Map<String, dynamic>,
  );

  /// Bookmarks the group. [source] is the screen it was saved from:
  /// `explore` or `group_detail` (BQ13).
  Future<void> save(int id, {required String source}) =>
      _api.put('/groups/$id/save', query: {'source': source});

  Future<void> unsave(int id) => _api.delete('/groups/$id/save');

  /// Submits the join form. [entryPoint] is how the profile was reached
  /// (BQ6); [joinAttemptId] is the id the form was opened with (BQ7).
  Future<void> join(
    int id, {
    required EntryPoint entryPoint,
    String? recRequestId,
    String? joinAttemptId,
    String? motivation,
  }) => _api.post(
    '/groups/$id/join',
    body: {
      'entry_point': entryPoint.name,
      'rec_request_id': ?recRequestId,
      'join_attempt_id': ?joinAttemptId,
      'motivation': ?motivation,
    },
  );

  /// Groups the student is an active member of, most recently joined first.
  Future<List<Rso>> mine() async => _list(await _api.get('/me/groups'));

  static List<Rso> _list(Object? json) => [
    for (final item in json as List) Rso.fromJson(item as Map<String, dynamic>),
  ];
}
