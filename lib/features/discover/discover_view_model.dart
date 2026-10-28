import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/group_filters.dart';
import '../../data/models/recommendation.dart';
import '../../data/models/rso.dart';
import '../../data/models/rso_category.dart';
import '../../data/repositories/groups_repository.dart';
import '../../data/repositories/recommendations_repository.dart';

/// The state behind [DiscoverScreen]: the filters, the search results and the
/// recommender's picks.
///
/// The screen only renders what this exposes and forwards what the student
/// does; searching, debouncing and the stale-response guard live here.
class DiscoverViewModel extends ChangeNotifier {
  DiscoverViewModel({
    required GroupsRepository groups,
    required RecommendationsRepository recommendations,
    required Analytics analytics,
    this.debounce = const Duration(milliseconds: 400),
    bool Function()? isOnline,
  }) : _groups = groups,
       _recommendationsRepository = recommendations,
       _analytics = analytics,
       _isOnline = isOnline ?? _alwaysOnline;

  static bool _alwaysOnline() => true;

  final GroupsRepository _groups;
  final RecommendationsRepository _recommendationsRepository;
  final Analytics _analytics;
  final bool Function() _isOnline;

  /// How long typing has to pause before the search is sent.
  final Duration debounce;

  GroupFilters _filters = const GroupFilters();
  GroupPage? _results;
  List<Rso> _featured = const [];
  GroupRecommendations? _recommendations;
  bool _recommendationsFailed = false;
  String? _error;
  bool _loading = false;
  bool _searchNeedsConnection = false;
  bool _disposed = false;

  Timer? _debounce;

  /// Only the latest search may update the list: an older, slower response
  /// arriving last would otherwise overwrite newer results.
  int _searchId = 0;

  GroupFilters get filters => _filters;
  GroupPage? get results => _results;

  /// Most popular groups, shown when recommendations can't be.
  List<Rso> get featured => _featured;

  GroupRecommendations? get recommendations => _recommendations;
  bool get recommendationsFailed => _recommendationsFailed;
  String? get error => _error;
  bool get loading => _loading;

  /// The student searched or filtered while offline. Searching runs on the
  /// backend, so the list keeps the groups saved on the phone instead.
  bool get searchNeedsConnection => _searchNeedsConnection;

  /// Whether the first answer (results or an error) has arrived.
  bool get ready => _results != null || _error != null;

  /// First load: the unfiltered list and the recommendations.
  void start() {
    search();
    loadRecommendations();
  }

  /// Fetched once per visit, since the backend logs each answer as shown
  /// (BQ2). Pull to refresh is the only other caller.
  Future<void> loadRecommendations() async {
    try {
      final recommendations = await _recommendationsRepository.groups();
      if (_disposed) return;
      _recommendations = recommendations;
      _recommendationsFailed = false;
    } on ApiException catch (e) {
      if (_disposed) return;
      _analytics.error(e, screen: Screens.discover);
      // Popular groups take the carousel's place.
      _recommendationsFailed = true;
    }
    notifyListeners();
  }

  /// Pull to refresh asks for new recommendations too.
  Future<void> refresh() => Future.wait([search(), loadRecommendations()]);

  Future<void> search() async {
    _debounce?.cancel();
    final searchId = ++_searchId;
    final filters = _filters;
    // Offline, a search can only fail: say so at once instead of waiting.
    _searchNeedsConnection = filters.isSearch && !_isOnline();
    if (_searchNeedsConnection) {
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final results = await _groups.search(filters);
      if (_disposed || searchId != _searchId) return;
      _results = results;
      _error = null;
      // Featured is the most popular groups: the first page of an unfiltered,
      // default-sorted browse.
      if (!filters.isSearch && filters.sort == GroupSort.popular) {
        _featured = results.items.take(3).toList();
      }
    } on ApiException catch (e) {
      if (_disposed || searchId != _searchId) return;
      _analytics.error(e, screen: Screens.discover);
      _error = e.message;
    } finally {
      if (!_disposed && searchId == _searchId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Typing is debounced so a word is one search, not one per letter.
  void setQuery(String value) {
    _filters = _filters.copyWith(query: value);
    _debounce?.cancel();
    _debounce = Timer(debounce, search);
  }

  void selectCategory(RsoCategory category) {
    _filters = _filters.copyWith(category: category);
    search();
  }

  /// The filters chosen in the filters sheet.
  void applyFilters(GroupFilters filters) {
    _filters = filters;
    search();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
