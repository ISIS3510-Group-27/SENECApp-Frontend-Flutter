import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/offline.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/models/join_sources.dart';
import '../../data/models/rso.dart';
import '../../data/repositories/join_sources_repository.dart';
import '../../state/connection_status.dart';
import '../shell/track_screen.dart';
import 'join_sources_view_model.dart';

/// "Where your members come from": BQ6 for a group's leaders. Which entry
/// points (recommendations, search and filters, Explore, notifications...)
/// bring the group its joins, how well each converts compared with the whole
/// campus, and what changed since the leader's last visit.
class JoinSourcesScreen extends StatelessWidget {
  const JoinSourcesScreen({super.key, required this.rso});

  final Rso rso;

  static Route<void> route(Rso rso) =>
      MaterialPageRoute<void>(builder: (_) => JoinSourcesScreen(rso: rso));

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final services = context.read<AppServices>();
        return JoinSourcesViewModel(
          groupId: rso.id,
          repository: services.joinSources,
          analytics: services.analytics,
          reconnected: context.read<ConnectionStatus>().reconnected,
        )..load();
      },
      child: _JoinSourcesBody(rso: rso),
    );
  }
}

class _JoinSourcesBody extends StatelessWidget {
  const _JoinSourcesBody({required this.rso});

  final Rso rso;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JoinSourcesViewModel>();
    final view = vm.view;
    final error = vm.error;

    return TrackScreen(
      name: Screens.joinSources,
      ready: vm.ready,
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => _refresh(context, vm),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                12,
                kPageGutter,
                kNavBarClearance,
              ),
              children: [
                _Header(rso: rso),
                const SizedBox(height: 20),
                if (view != null)
                  ..._content(context, view, refreshing: vm.refreshing)
                else if (error != null)
                  ErrorBlock(
                    message: error.message,
                    onRetry: () => vm.load(force: true),
                    offlineMessage:
                        'This is worked out from what students do in the app, '
                        'so the first look needs a connection. After that it '
                        'opens without one.',
                  )
                else
                  const LoadingBlock(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context, JoinSourcesViewModel vm) {
    if (!context.read<ConnectionStatus>().online && vm.view != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You're offline. This is the copy saved on your phone; it "
            'updates when the connection is back.',
          ),
        ),
      );
      return Future.value();
    }
    return vm.load(force: true);
  }

  List<Widget> _content(
    BuildContext context,
    JoinSourcesView view, {
    required bool refreshing,
  }) {
    final answer = view.current;
    final savedAt = view.savedAt;
    final previous = view.previous;

    return [
      if (savedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SavedNote(savedAt: savedAt, refreshing: refreshing),
        ),
      Row(
        children: [
          Expanded(
            child: StatTile(
              value: '${answer.joins}',
              label: 'joins in ${answer.days} days',
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              value: '${answer.views}',
              label: 'profile views',
              color: AppColors.teal,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              value: _percent(
                answer.views == 0 ? null : answer.joins / answer.views,
              ),
              label: 'views that join',
              color: AppColors.violet,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(answer.answer, style: AppTheme.heading(size: 15)),
            const SizedBox(height: 8),
            Text(
              'On the whole campus: ${answer.campusAnswer}',
              style: AppTheme.body(
                size: 12,
                height: 1.4,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      if (previous != null) ...[
        const SizedBox(height: 10),
        Text(
          'Compared with your visit ${Dates.ago(previous.takenAt)}.',
          style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
        ),
      ],
      const SizedBox(height: 20),
      if (answer.sources.isEmpty)
        Text(
          'Nobody has opened or joined the group from the app in the last '
          '${answer.days} days yet.',
          style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
        )
      else ...[
        const SectionLabel(text: 'By entry point'),
        const SizedBox(height: 10),
        for (final source in answer.sources) ...[
          _SourceCard(
            source: source,
            newJoins: view.newJoins(source.entryPoint),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Text(
          'A profile view counts each time a student opens the group page. '
          'The campus rate is the same entry point for every group.',
          style: AppTheme.body(
            size: 11,
            height: 1.4,
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.rso});

  final Rso rso;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoundIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          size: 36,
          iconSize: 17,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where your members come from',
                style: AppTheme.heading(size: 20),
              ),
              Text(
                'How students found ${rso.name} before joining it.',
                style: AppTheme.body(
                  size: 12,
                  height: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The saved copy's age; while a newer answer loads, says so instead of the
/// offline explanation.
class _SavedNote extends StatelessWidget {
  const _SavedNote({required this.savedAt, required this.refreshing});

  final DateTime savedAt;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectionStatus>().online;
    final age = Dates.ago(savedAt);
    if (!online) {
      return OfflineNote(
        'Saved $age on this phone. New joins show up here once you are back '
        'online; it refreshes by itself.',
      );
    }
    return Text(
      refreshing ? 'Saved $age · updating…' : 'Saved $age · could not update',
      style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source, required this.newJoins});

  final JoinSource source;
  final int? newJoins;

  @override
  Widget build(BuildContext context) {
    final share = source.shareOfJoins ?? 0;
    final rate = source.viewToJoinRate;
    final campus = source.campusViewToJoinRate;
    final delta = newJoins;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(source.entryPoint), size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _label(source.entryPoint),
                  style: AppTheme.body(size: 14, weight: FontWeight.w700),
                ),
              ),
              Text(
                '${source.joins} ${source.joins == 1 ? 'join' : 'joins'}',
                style: AppTheme.body(size: 13, weight: FontWeight.w700),
              ),
              if (delta != null && delta > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '+$delta',
                    style: AppTheme.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: AppColors.cardMuted,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_percent(share)} of your joins · ${source.views} views · '
            '${_percent(rate)} join (campus ${_percent(campus)})',
            style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

String _percent(double? value) =>
    value == null ? '–' : '${(value * 100).round()}%';

String _label(String entryPoint) => switch (entryPoint) {
  'recommendation' => 'Recommended for you',
  'search' => 'Search and filters',
  'explore' => 'Browsing Explore',
  'notification' => 'Notifications',
  'event' => 'From an event page',
  'direct' => 'Direct link or My RSOs',
  _ => entryPoint,
};

IconData _icon(String entryPoint) => switch (entryPoint) {
  'recommendation' => Icons.auto_awesome_rounded,
  'search' => Icons.search_rounded,
  'explore' => Icons.explore_rounded,
  'notification' => Icons.notifications_rounded,
  'event' => Icons.event_rounded,
  _ => Icons.link_rounded,
};
