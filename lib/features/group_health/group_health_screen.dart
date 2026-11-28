import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/concurrency/run_isolated.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/group_health.dart';
import '../../data/models/rso.dart';
import '../../data/repositories/group_health_repository.dart';
import '../shell/track_screen.dart';

class GroupHealthScreen extends StatefulWidget {
  const GroupHealthScreen({super.key, required this.rso});

  final Rso rso;

  static Route<void> route(Rso rso) =>
      MaterialPageRoute<void>(builder: (_) => GroupHealthScreen(rso: rso));

  @visibleForTesting
  static Future<HealthTrend> Function(List<int> weeks) computeTrend =
      (weeks) => runIsolated(HealthTrend.of, weeks);

  @override
  State<GroupHealthScreen> createState() => _GroupHealthScreenState();
}

class _GroupHealthScreenState extends State<GroupHealthScreen> {
  HealthResult? _result;
  HealthTrend? _trend;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) {
    setState(() => _error = null);
    final health = context.read<AppServices>().health;
    return health
        .load(widget.rso.id, force: force)
        .then((result) async {
          final weeks = result.health.attendance;
          final trend = await GroupHealthScreen.computeTrend(weeks);
          if (!mounted) return;
          setState(() {
            _result = result;
            _trend = trend;
          });
        })
        .catchError((Object error) {
          if (!mounted) return;
          reportError(context, error, screen: Screens.groupHealth);
          setState(() => _error = (error as ApiException).message);
        }, test: (error) => error is ApiException);
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.groupHealth,
    ready: _result != null || _error != null,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final result = _result;
    final trend = _trend;

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
                        Text('Group health', style: AppTheme.heading(size: 20)),
                        Text(
                          'How attendance at ${widget.rso.name} changed over '
                          'the last 8 weeks.',
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
              if (_error case final error? when result == null)
                ErrorBlock(
                  message: error,
                  onRetry: () => _load(force: true),
                  offlineMessage:
                      'Attendance trends come from check-ins on the server, '
                      'so they need a connection the first time.',
                )
              else if (result == null || trend == null)
                const LoadingBlock()
              else
                ..._content(result, trend),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(HealthResult result, HealthTrend trend) {
    final health = result.health;
    final savedAt = result.savedAt;

    return [
      if (savedAt != null) ...[
        _SavedNote(savedAt: savedAt),
        const SizedBox(height: 12),
      ],
      _StatusCard(health: health, trend: trend),
      const SizedBox(height: 20),
      const SectionLabel(text: 'Check-ins per week'),
      const SizedBox(height: 10),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: _AttendancePainter(
                    weeks: health.attendance,
                    trend: trend,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Bars are check-ins per week, oldest on the left. The line is '
              'the ${HealthTrend.window}-week average.',
              style: AppTheme.body(
                size: 11,
                height: 1.4,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
      if (health.reengagement case final reengagement?) ...[
        const SizedBox(height: 20),
        const SectionLabel(text: 'Re-engagement'),
        const SizedBox(height: 10),
        _CaseCard(reengagement: reengagement),
      ],
      const SizedBox(height: 20),
      const SectionLabel(text: 'What brings members back'),
      const SizedBox(height: 10),
      if (health.arms.isEmpty)
        Text(
          'No group has needed re-engagement yet.',
          style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
        )
      else
        for (final arm in health.arms) ...[
          _ArmRow(arm: arm),
          const SizedBox(height: 8),
        ],
      const SizedBox(height: 12),
      Text(
        health.answer,
        style: AppTheme.body(
          size: 12,
          height: 1.45,
          color: AppColors.mutedForeground,
        ),
      ),
    ];
  }
}

class _SavedNote extends StatelessWidget {
  const _SavedNote({required this.savedAt});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.history_rounded,
            size: 16,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Saved ${Dates.ago(savedAt)}. Pull down to refresh when '
              "you're online.",
              style: AppTheme.body(
                size: 12,
                height: 1.4,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.health, required this.trend});

  final GroupHealth health;
  final HealthTrend trend;

  @override
  Widget build(BuildContext context) {
    final declining = health.declining;
    final change = trend.lastChange;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            declining
                ? Icons.trending_down_rounded
                : Icons.trending_flat_rounded,
            size: 22,
            color: declining ? AppColors.orange : AppColors.teal,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  declining ? 'Attendance is dropping' : 'Attendance is steady',
                  style: AppTheme.heading(size: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Last 4 weeks ${_number(health.recent)} check-ins a week, '
                  'before that ${_number(health.baseline)}.'
                  '${declining ? ' That is ${(health.declinePct * 100).round()}% less.' : ''}',
                  style: AppTheme.body(
                    size: 13,
                    height: 1.45,
                    color: AppColors.bodyForeground,
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last week ${change >= 0 ? 'up' : 'down'} '
                    '${(change.abs() * 100).round()}% from the week before.',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.mutedForeground,
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

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.reengagement});

  final HealthCase reengagement;

  @override
  Widget build(BuildContext context) {
    final rate = reengagement.returnRate;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${armLabel(reengagement.arm)} '
            '${reengagement.active ? 'running' : 'finished'}',
            style: AppTheme.body(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${reengagement.returnedMembers} of ${reengagement.lapsedMembers} '
            'members who stopped coming are back'
            '${rate == null ? '.' : ' (${(rate * 100).round()}%).'}',
            style: AppTheme.body(
              size: 12,
              height: 1.4,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArmRow extends StatelessWidget {
  const _ArmRow({required this.arm});

  final ReengagementRate arm;

  @override
  Widget build(BuildContext context) {
    final rate = arm.rate;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  armLabel(arm.arm),
                  style: AppTheme.body(size: 14, weight: FontWeight.w700),
                ),
                Text(
                  '${arm.returned} of ${arm.lapsed} members back, '
                  '${arm.groups} ${arm.groups == 1 ? 'group' : 'groups'}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Text(
            rate == null ? 'No data' : '${(rate * 100).round()}%',
            style: AppTheme.heading(size: 16),
          ),
        ],
      ),
    );
  }
}

class _AttendancePainter extends CustomPainter {
  _AttendancePainter({required this.weeks, required this.trend});

  final List<int> weeks;
  final HealthTrend trend;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;
    final top = trend.peak == 0 ? 1 : trend.peak;
    final slot = size.width / weeks.length;
    final barWidth = slot * 0.55;
    final bars = Paint()..color = AppColors.accent.withValues(alpha: 0.75);
    for (var i = 0; i < weeks.length; i++) {
      final height = size.height * weeks[i] / top;
      final left = slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          const Radius.circular(4),
        ),
        bars,
      );
    }
    final line = Path();
    for (var i = 0; i < trend.average.length; i++) {
      final x = slot * i + slot / 2;
      final y = size.height - size.height * trend.average[i] / top;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.foreground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_AttendancePainter oldDelegate) =>
      !identical(oldDelegate.trend, trend) || oldDelegate.weeks != weeks;
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
