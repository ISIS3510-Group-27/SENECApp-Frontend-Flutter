import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/insight_age_note.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/leader_insights.dart';
import '../../data/models/rso.dart';
import '../../data/repositories/insights_repository.dart';
import '../shell/track_screen.dart';

class ProfileTipsScreen extends StatefulWidget {
  const ProfileTipsScreen({super.key, required this.rso});

  final Rso rso;

  static Route<void> route(Rso rso) =>
      MaterialPageRoute<void>(builder: (_) => ProfileTipsScreen(rso: rso));

  @override
  State<ProfileTipsScreen> createState() => _ProfileTipsScreenState();
}

class _ProfileTipsScreenState extends State<ProfileTipsScreen> {
  ProfileTips? _tips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final tips = await context.read<AppServices>().insights.profileTips(
        widget.rso.id,
        force: force,
      );
      if (mounted) setState(() => _tips = tips);
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.profileTips);
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.profileTips,
    ready: _tips != null || _error != null,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final tips = _tips;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
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
                          'Improve your profile',
                          style: AppTheme.heading(size: 20),
                        ),
                        Text(
                          'Which profile fields students respond to, and which '
                          'ones ${widget.rso.name} is still missing.',
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
              ),
              const SizedBox(height: 20),
              if (_error case final error?)
                ErrorBlock(
                  message: error,
                  onRetry: () => _load(force: true),
                  offlineMessage:
                      'These tips are worked out from what students do in the '
                      'app, so they need a connection.',
                )
              else if (tips == null)
                const LoadingBlock()
              else
                ..._content(tips),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(ProfileTips tips) => [
    InsightAgeNote(
      dataKeys: [InsightKeys.profileTips(widget.rso.id)],
      message: "These tips update when you're online.",
      padding: const EdgeInsets.only(bottom: 12),
    ),
    AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${tips.filled} of ${tips.total} profile fields filled',
            style: AppTheme.heading(size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            tips.answer,
            style: AppTheme.body(
              size: 13,
              height: 1.45,
              color: AppColors.bodyForeground,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    if (tips.missing.isEmpty)
      Text(
        'Every field is filled in.',
        style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
      )
    else ...[
      const SectionLabel(text: 'Still missing'),
      const SizedBox(height: 10),
      for (final field in tips.missing) ...[
        _MissingField(field: field),
        const SizedBox(height: 8),
      ],
    ],
    if (tips.present.isNotEmpty) ...[
      const SizedBox(height: 12),
      const SectionLabel(text: 'Already there'),
      const SizedBox(height: 10),
      for (final field in tips.present) _PresentField(field: field),
    ],
  ];
}

class _MissingField extends StatelessWidget {
  const _MissingField({required this.field});

  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    final hint = _hint(field.field);

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.add_circle_outline_rounded,
            size: 20,
            color: AppColors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(field.field),
                  style: AppTheme.body(size: 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _evidence(field),
                  style: AppTheme.body(
                    size: 12,
                    height: 1.4,
                    color: AppColors.mutedForeground,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: AppTheme.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresentField extends StatelessWidget {
  const _PresentField({required this.field});

  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(width: 10),
          Text(_label(field.field), style: AppTheme.body(size: 13)),
        ],
      ),
    );
  }
}

String _label(String field) => switch (field) {
  'has_image' => 'Cover photo',
  'has_contact_email' => 'Contact email',
  'has_instagram' => 'Instagram link',
  'has_website' => 'Website',
  'has_meeting_building' => 'Meeting place',
  'has_founded_year' => 'Founding year',
  'has_upcoming_event' => 'An upcoming event',
  _ => field,
};

String? _hint(String field) => switch (field) {
  'has_image' => 'Use "Change cover photo" on the group page.',
  'has_upcoming_event' => 'Use "Create event" on the group page.',
  _ => null,
};

String _evidence(ProfileField field) {
  const noLink = 'Not linked to more saves or joins so far.';
  final lift = field.lift;
  final correlation = field.correlation;
  if (lift != null) {
    return lift > 1
        ? 'Profiles with it turn ${lift.toStringAsFixed(1)}x more views into '
              'saves or joins.'
        : noLink;
  }
  if (correlation != null) {
    return correlation > 0
        ? 'Positively linked to saves and joins '
              '(r = ${correlation.toStringAsFixed(2)}).'
        : noLink;
  }
  return 'Not enough profile views yet to say how much it matters.';
}
