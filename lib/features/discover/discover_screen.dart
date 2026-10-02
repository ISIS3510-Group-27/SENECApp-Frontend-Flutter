import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/assets/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/org_image.dart';
import '../../core/widgets/rso_list_tile.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/api/api_client.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/group_filters.dart';
import '../../data/models/recommendation.dart';
import '../../data/models/rso.dart';
import '../../data/models/rso_category.dart';
import '../../data/repositories/groups_repository.dart';
import '../../state/app_state.dart';
import '../notifications/notifications_screen.dart';
import '../recommendations/recommendations_screen.dart';
import '../rso_detail/rso_detail_screen.dart';
import 'filters_sheet.dart';

/// Landing tab: search, filter, browse, open
///
/// Search and filters run on the backend, which logs each search it receives
/// (BQ5, BQ12). Typing is debounced so a word is one search, not one per
/// letter.
///
/// Above the results, the recommender's picks for the student (the smart
/// feature). They are fetched once per visit, since the backend logs each
/// answer as shown (BQ2).
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onCreateRso});

  /// Pushing the create form is the shell's job, because the form is a sibling
  /// of this screen in the Discover stack rather than a child of it.
  final VoidCallback onCreateRso;

  /// How long typing has to pause before the search is sent.
  static const searchDebounce = Duration(milliseconds: 400);

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();

  GroupFilters _filters = const GroupFilters();
  GroupPage? _results;

  /// Most popular groups, shown when recommendations can't be.
  List<Rso> _featured = const [];

  GroupRecommendations? _recommendations;
  bool _recommendationsFailed = false;
  String? _error;
  bool _loading = false;

  Timer? _debounce;

  /// Only the latest search may update the list: an older, slower response
  /// arriving last would otherwise overwrite newer results.
  int _searchId = 0;

  late final GroupsRepository _groups = context.read<AppServices>().groups;

  @override
  void initState() {
    super.initState();
    _search();
    _loadRecommendations();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecommendations() async {
    try {
      final recommendations = await context
          .read<AppServices>()
          .recommendations
          .groups();
      if (!mounted) return;
      setState(() {
        _recommendations = recommendations;
        _recommendationsFailed = false;
      });
    } on ApiException {
      // Popular groups take the carousel's place.
      if (mounted) setState(() => _recommendationsFailed = true);
    }
  }

  /// Pull to refresh asks for new recommendations too.
  Future<void> _refresh() => Future.wait([_search(), _loadRecommendations()]);

  Future<void> _search() async {
    _debounce?.cancel();
    final searchId = ++_searchId;
    final filters = _filters;
    setState(() => _loading = true);
    try {
      final results = await _groups.search(filters);
      if (!mounted || searchId != _searchId) return;
      setState(() {
        _results = results;
        _error = null;
        // Featured is the most popular groups: the first page of an unfiltered,
        // default-sorted browse.
        if (!filters.isSearch && filters.sort == GroupSort.popular) {
          _featured = results.items.take(3).toList();
        }
      });
    } on ApiException catch (e) {
      if (!mounted || searchId != _searchId) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted && searchId == _searchId) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    _filters = _filters.copyWith(query: value);
    _debounce?.cancel();
    _debounce = Timer(DiscoverScreen.searchDebounce, _search);
  }

  void _onCategorySelected(RsoCategory category) {
    _filters = _filters.copyWith(category: category);
    _search();
  }

  Future<void> _openFilters() async {
    final chosen = await FiltersSheet.show(
      context,
      current: _filters,
      catalog: context.read<AppServices>().catalog,
    );
    if (chosen == null || !mounted) return;
    _filters = chosen;
    _search();
  }

  /// Groups opened from narrowed results were found by searching; the rest by
  /// browsing. The backend compares the two (BQ6, BQ12, BQ13).
  void _openRecommendation(GroupRecommendation item) {
    Navigator.of(context).push(
      RsoDetailScreen.route(
        item.group.id,
        entryPoint: EntryPoint.recommendation,
        recRequestId: _recommendations!.requestId,
        preview: item.group,
      ),
    );
  }

  void _openRso(Rso rso, {bool fromFeatured = false}) {
    final entryPoint = !fromFeatured && _filters.isSearch
        ? EntryPoint.search
        : EntryPoint.explore;
    Navigator.of(
      context,
    ).push(RsoDetailScreen.route(rso.id, entryPoint: entryPoint, preview: rso));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final state = context.watch<AppState>();
    // Groups joined since the list was fetched stop being suggestions.
    final recommended = [
      for (final item
          in _recommendations?.items ?? const <GroupRecommendation>[])
        if (!state.isMember(item.group)) item,
    ];
    // The carousels are a browsing aid, so they only show when the student
    // isn't actively searching or filtering.
    final browsing = !_filters.isSearch;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: kNavBarClearance),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
            child: _Header(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 0),
            child: Row(
              children: [
                Expanded(
                  child: _SearchField(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                RoundIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'Filters',
                  size: 48,
                  iconSize: 20,
                  showDot:
                      _filters.sheetCount > 0 ||
                      _filters.sort != GroupSort.popular,
                  onPressed: _openFilters,
                ),
              ],
            ),
          ),
          if (browsing && recommended.isNotEmpty) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
              child: SectionLabel(
                text: 'Recommended for you',
                trailing: _SeeAllButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(RecommendationsScreen.route(_recommendations!)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FeaturedCarousel(
              rsos: [for (final item in recommended.take(5)) item.group],
              reasons: [
                for (final item in recommended.take(5))
                  item.reasons.firstOrNull,
              ],
              onSelect: (index) => _openRecommendation(recommended[index]),
            ),
            // Popular groups instead, once recommendations failed or ran out
            // (the student joined them all).
          ] else if (browsing &&
              (_recommendationsFailed || _recommendations != null) &&
              _featured.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: kPageGutter),
              child: SectionLabel(text: 'Featured'),
            ),
            const SizedBox(height: 12),
            _FeaturedCarousel(
              rsos: _featured,
              onSelect: (index) =>
                  _openRso(_featured[index], fromFeatured: true),
            ),
          ],
          const SizedBox(height: 20),
          _CategoryRow(
            selected: _filters.category,
            onSelected: _onCategorySelected,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
            child: SectionLabel(
              text: results == null
                  ? 'Organizations'
                  : '${results.total} '
                        'Organization${results.total == 1 ? '' : 's'}',
              trailing: _NewRsoButton(onPressed: widget.onCreateRso),
            ),
          ),
          const SizedBox(height: 12),
          if (_error case final error?)
            ErrorBlock(message: error, onRetry: _search)
          else if (results == null)
            const LoadingBlock()
          else if (results.items.isEmpty)
            const _EmptyResults()
          else ...[
            // Results stay on screen while a newer search loads.
            if (_loading)
              const Padding(
                padding: EdgeInsets.fromLTRB(kPageGutter, 0, kPageGutter, 12),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.accent,
                  backgroundColor: Colors.transparent,
                ),
              ),
            for (final rso in results.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kPageGutter,
                  0,
                  kPageGutter,
                  12,
                ),
                child: RsoListTile(rso: rso, onTap: () => _openRso(rso)),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final unread = context.select<AppState, int>((s) => s.unreadCount);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.asset(
            BrandAssets.logo,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'UNIANDES · BOGOTÁ',
                style: AppTheme.body(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.mutedForeground,
                  letterSpacing: 1.8,
                ),
              ),
              Text('SENECApp', style: AppTheme.heading(size: 24, height: 1.15)),
            ],
          ),
        ),
        RoundIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notifications',
          showDot: unread > 0,
          onPressed: () =>
              Navigator.of(context).push(NotificationsScreen.route()),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// The keyboard's search key: search now instead of after the pause.
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: AppTheme.body(size: 14),
      decoration: InputDecoration(
        hintText: 'Search organizations...',
        filled: true,
        fillColor: AppColors.secondary,
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: AppColors.mutedForeground,
        ),
        suffixIcon: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppColors.mutedForeground,
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    onSubmitted('');
                  },
                ),
        ),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(AppColors.primary),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    borderSide: BorderSide(color: color),
  );
}

class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({
    required this.rsos,
    required this.onSelect,
    this.reasons,
  });

  final List<Rso> rsos;

  /// Called with the tapped card's index.
  final ValueChanged<int> onSelect;

  /// One line per card on why it was recommended, in the order of [rsos].
  final List<String?>? reasons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
        itemCount: rsos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _FeaturedCard(
          rso: rsos[index],
          reason: reasons?[index],
          onTap: () => onSelect(index),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.rso, required this.onTap, this.reason});

  final Rso rso;
  final VoidCallback onTap;

  /// Why it was recommended; takes the category line's place.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(AppRadius.hero),
      clipBehavior: Clip.antiAlias,
      color: AppColors.card,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 208,
          child: Stack(
            fit: StackFit.expand,
            children: [
              OrgImage(rso: rso, iconSize: 38),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      rso.color.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.6],
                  ),
                ),
              ),
              if (rso.verified)
                const Positioned(top: 12, right: 12, child: OfficialBadge()),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reason case final reason?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: RecommendationReason(
                          text: reason,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      )
                    else
                      Text(
                        rso.category.label.toUpperCase(),
                        style: AppTheme.body(
                          size: 11,
                          weight: FontWeight.w700,
                          color: AppColors.accent.withValues(alpha: 0.85),
                          letterSpacing: 1.2,
                        ),
                      ),
                    Text(
                      rso.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 14,
                        height: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rso.members} members',
                      style: AppTheme.body(
                        size: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.selected, required this.onSelected});

  final RsoCategory selected;
  final ValueChanged<RsoCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
        itemCount: RsoCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = RsoCategory.values[index];
          return SelectableChip.category(
            label: category.label,
            icon: category.icon,
            selected: category == selected,
            onSelected: (_) => onSelected(category),
          );
        },
      ),
    );
  }
}

class _NewRsoButton extends StatelessWidget {
  const _NewRsoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_rounded,
                size: 14,
                color: AppColors.background,
              ),
              const SizedBox(width: 4),
              Text(
                'New RSO',
                style: AppTheme.body(
                  size: 12,
                  weight: FontWeight.w800,
                  color: AppColors.background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageGutter,
        vertical: 40,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 40,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text('No organizations match', style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Try another category, or a different search term.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          'See all',
          style: AppTheme.body(
            size: 12,
            weight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
