import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/org_image.dart';
import '../../core/widgets/rso_list_tile.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/rso.dart';
import '../../data/models/rso_category.dart';
import '../../state/app_state.dart';
import '../notifications/notifications_screen.dart';
import '../rso_detail/rso_detail_screen.dart';

/// The landing tab: search, filter, browse, open.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onCreateRso});

  /// Pushing the create form is the shell's job, because the form is a sibling
  /// of this screen in the Discover stack rather than a child of it.
  final VoidCallback onCreateRso;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();

  RsoCategory _category = RsoCategory.all;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The carousel is a browsing aid, so it steps aside as soon as the student
  /// starts narrowing the list - otherwise it just pushes results off-screen.
  bool get _showFeatured => _query.isEmpty && _category == RsoCategory.all;

  void _openRso(Rso rso) {
    Navigator.of(context).push(RsoDetailScreen.route(rso.id));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final results = state.discover(category: _category, query: _query);

    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarClearance),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: _Header(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 0),
          child: _SearchField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (_showFeatured) ...[
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kPageGutter),
            child: SectionLabel(text: 'Featured'),
          ),
          const SizedBox(height: 12),
          _FeaturedCarousel(rsos: state.featured, onSelect: _openRso),
        ],
        const SizedBox(height: 20),
        _CategoryRow(
          selected: _category,
          onSelected: (category) => setState(() => _category = category),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: SectionLabel(
            text:
                '${results.length} '
                'Organization${results.length == 1 ? '' : 's'}',
            trailing: _NewRsoButton(onPressed: widget.onCreateRso),
          ),
        ),
        const SizedBox(height: 12),
        if (results.isEmpty)
          const _EmptyResults()
        else
          for (final rso in results)
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
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
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
  const _FeaturedCarousel({required this.rsos, required this.onSelect});

  final List<Rso> rsos;
  final ValueChanged<Rso> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
        itemCount: rsos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            _FeaturedCard(rso: rsos[index], onTap: () => onSelect(rsos[index])),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.rso, required this.onTap});

  final Rso rso;
  final VoidCallback onTap;

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
            // Re-tapping the active chip keeps it active rather than clearing
            // it: the list must always be showing *something*.
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
