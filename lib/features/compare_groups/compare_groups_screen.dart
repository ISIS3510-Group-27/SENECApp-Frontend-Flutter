import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/offline.dart';
import '../../core/widgets/org_image.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/local/recommendation_snapshot_store.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/recommendation.dart';
import '../../state/connection_status.dart';
import '../rso_detail/rso_detail_screen.dart';
import '../shell/track_screen.dart';
import 'compare_groups_view_model.dart';

/// Compares two choices from the same recommendation response.
class CompareGroupsScreen extends StatefulWidget {
  const CompareGroupsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const CompareGroupsScreen());

  @override
  State<CompareGroupsScreen> createState() => _CompareGroupsScreenState();
}

class _CompareGroupsScreenState extends State<CompareGroupsScreen> {
  late final CompareGroupsViewModel _vm = () {
    final services = context.read<AppServices>();
    return CompareGroupsViewModel(
      recommendations: services.recommendations,
      sessionVersion: () => services.offline.sessionVersion,
      snapshots: RecommendationSnapshotStore(store: services.offline.store),
      isOnline: () => isOnline(context, listen: false),
    );
  }();

  StreamSubscription<void>? _reconnected;

  @override
  void initState() {
    super.initState();
    _load();
    _reconnected = context.read<ConnectionStatus?>()?.reconnected.listen((
      _,
    ) async {
      await _vm.refreshAfterReconnect();
      _reportFailure();
    });
  }

  Future<void> _load() async {
    await _vm.load();
    _reportFailure();
  }

  void _reportFailure() {
    if (!mounted) return;
    if (_vm.failure case final error?) {
      context.read<AppServices>().analytics.error(
        error,
        screen: Screens.compareGroups,
      );
    }
  }

  void _open(int id) {
    // Read both the group and its attribution from the current response.
    if (!_vm.canOpenGroup || !isOnline(context, listen: false)) return;
    final result = _vm.result;
    if (result == null) return;
    for (final item in result.items) {
      if (item.group.id != id) continue;
      Navigator.of(context).push(
        RsoDetailScreen.route(
          id,
          entryPoint: EntryPoint.recommendation,
          recRequestId: result.requestId,
          preview: item.group,
        ),
      );
      return;
    }
  }

  @override
  void dispose() {
    _reconnected?.cancel();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _vm,
    builder: (context, _) => TrackScreen(
      name: Screens.compareGroups,
      ready: _vm.ready,
      child: _buildScreen(context),
    ),
  );

  Widget _buildScreen(BuildContext context) {
    final online = isOnline(context);
    final first = _vm.first;
    final second = _vm.second;
    final canOpen = online && _vm.canOpenGroup;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            kPageGutter,
            12,
            kPageGutter,
            kNavBarClearance,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  size: 48,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Compare recommended groups',
                    style: AppTheme.heading(size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Choose two communities and compare what they offer.',
              style: AppTheme.body(
                size: 13,
                height: 1.45,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            if (_vm.savedAt case final savedAt?) ...[
              OfflineNote(
                'Showing recommendations saved ${Dates.ago(savedAt)}. '
                'You can compare them. Refresh with a connection to open an organization.',
              ),
              const SizedBox(height: 16),
            ] else if (!online) ...[
              const OfflineNote(
                'Reconnect to refresh recommendations and open an organization.',
              ),
              const SizedBox(height: 16),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _vm.loading ? null : _load,
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  _vm.fromCache ? 'Retry' : 'Refresh recommendations',
                ),
              ),
            ),
            if (_vm.loading)
              const LoadingBlock()
            else if (_vm.error case final error?)
              ErrorBlock(
                message: error,
                onRetry: _load,
                offlineMessage: 'Connect to load recommendations.',
              )
            else if (!_vm.hasEnoughGroups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'You need at least two recommendations to compare. '
                  'Check back soon or refresh your recommendations.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 14, height: 1.45),
                ),
              )
            else ...[
              AppCard(
                child: Column(
                  children: [
                    _GroupPicker(
                      label: 'First organization',
                      selected: first,
                      items: _vm.items,
                      excludedId: second?.group.id,
                      onChanged: _vm.selectFirst,
                    ),
                    const SizedBox(height: 20),
                    _GroupPicker(
                      label: 'Second organization',
                      selected: second,
                      items: _vm.items,
                      excludedId: first?.group.id,
                      onChanged: _vm.selectSecond,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (first != null && second != null) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _ComparedGroup(
                        recommendation: first,
                        onOpen: canOpen ? () => _open(first.group.id) : null,
                      ),
                      _ComparedGroup(
                        recommendation: second,
                        onOpen: canOpen ? () => _open(second.group.id) : null,
                      ),
                    ];
                    final enlarged =
                        MediaQuery.textScalerOf(context).scale(16) > 21;
                    if (constraints.maxWidth < 300 || enlarged) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cards[0],
                          const SizedBox(height: 12),
                          cards[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                AppCard(
                  child: Column(
                    children: [
                      _ComparisonField(
                        label: 'Category',
                        first: first.group.category.label,
                        second: second.group.category.label,
                      ),
                      const Divider(height: 32),
                      _ComparisonField(
                        label: 'Members',
                        first: '${first.group.members}',
                        second: '${second.group.members}',
                      ),
                      const Divider(height: 32),
                      _ComparisonField(
                        label: 'Description',
                        first: first.group.description,
                        second: second.group.description,
                      ),
                      const Divider(height: 32),
                      _ComparisonField(
                        label: 'Recommendation reasons',
                        first: first.reasons.join('\n\n'),
                        second: second.reasons.join('\n\n'),
                      ),
                    ],
                  ),
                ),
              ] else
                Text(
                  'Select both organizations to see their comparison.',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.mutedForeground,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupPicker extends StatelessWidget {
  const _GroupPicker({
    required this.label,
    required this.selected,
    required this.items,
    required this.excludedId,
    required this.onChanged,
  });

  final String label;
  final GroupRecommendation? selected;
  final List<GroupRecommendation> items;
  final int? excludedId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    isEmpty: selected == null,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        key: ValueKey(label),
        value: selected?.group.id,
        isExpanded: true,
        hint: Text('Choose organization', style: AppTheme.body(size: 13)),
        style: AppTheme.body(size: 13),
        dropdownColor: AppColors.card,
        items: [
          for (final item in items)
            if (item.group.id != excludedId)
              DropdownMenuItem(
                value: item.group.id,
                child: Text(
                  item.group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}

class _ComparedGroup extends StatelessWidget {
  const _ComparedGroup({required this.recommendation, required this.onOpen});

  final GroupRecommendation recommendation;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final group = recommendation.group;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: SizedBox(
              height: 96,
              width: double.infinity,
              child: OrgImage(rso: group),
            ),
          ),
          const SizedBox(height: 12),
          Text(group.name, style: AppTheme.heading(size: 16)),
          const SizedBox(height: 8),
          TextButton(
            key: ValueKey('open-compared-group-${group.id}'),
            onPressed: onOpen,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              foregroundColor: AppColors.accent,
            ),
            child: const Text('View organization', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _ComparisonField extends StatelessWidget {
  const _ComparisonField({
    required this.label,
    required this.first,
    required this.second,
  });

  final String label;
  final String first;
  final String second;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppTheme.sectionLabel),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _value(first)),
          const SizedBox(width: 12),
          Expanded(child: _value(second)),
        ],
      ),
    ],
  );

  Widget _value(String text) => Text(
    text.trim().isEmpty ? 'Not provided' : text,
    style: AppTheme.body(size: 13, height: 1.5),
  );
}
