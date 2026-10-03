import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/badges.dart';
import '../../core/widgets/org_image.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/rso.dart';
import '../../data/storage/photo_storage.dart';
import '../../state/app_state.dart';
import '../create_event/create_event_screen.dart';
import '../event_detail/event_detail_screen.dart';
import '../shell/track_screen.dart';
import 'join_form_sheet.dart';

/// Level two of the hierarchy, and the deepest the app goes: from here the
/// student can join, which is the whole point of Discover.
///
/// The profile is fetched once per visit: the backend records each fetch as a
/// view, with [entryPoint] saying how the student got here.
class RsoDetailScreen extends StatefulWidget {
  const RsoDetailScreen({
    super.key,
    required this.rsoId,
    required this.entryPoint,
    this.recRequestId,
    this.preview,
  });

  final int rsoId;
  final EntryPoint entryPoint;

  /// The recommendation list this group was picked from, so the view and a
  /// join count for it (BQ2). Only with [EntryPoint.recommendation].
  final String? recRequestId;

  /// The list item that was tapped, shown while the full profile loads.
  final Rso? preview;

  /// Pushed onto whichever tab's navigator the student came from, which is what
  /// makes backing out return them to that tab.
  static Route<void> route(
    int rsoId, {
    required EntryPoint entryPoint,
    String? recRequestId,
    Rso? preview,
  }) => MaterialPageRoute<void>(
    builder: (_) => RsoDetailScreen(
      rsoId: rsoId,
      entryPoint: entryPoint,
      recRequestId: recRequestId,
      preview: preview,
    ),
  );

  @override
  State<RsoDetailScreen> createState() => _RsoDetailScreenState();
}

class _RsoDetailScreenState extends State<RsoDetailScreen> {
  Rso? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await context.read<AppServices>().groups.detail(
        widget.rsoId,
        entryPoint: widget.entryPoint,
        recRequestId: widget.recRequestId,
      );
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.groupDetail);
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.groupDetail,
    ready: _detail != null || _error != null,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final rso = _detail ?? widget.preview;

    if (rso == null) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 0),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  size: 36,
                  iconSize: 17,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (_error case final error?)
                ErrorBlock(message: error, onRetry: _load)
              else
                const LoadingBlock(),
            ],
          ),
        ),
      );
    }

    final detail = _detail;
    final state = context.watch<AppState>();
    final joined = state.isMember(rso);
    // Counts the student straight away when they joined during this visit.
    final members = rso.members + (joined && !rso.isMember ? 1 : 0);

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _Cover(rso: rso, saved: state.isSaved(rso)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kPageGutter,
                  20,
                  kPageGutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatsRow(rso: rso, members: members, detail: detail),
                    if (!rso.isApproved) ...[
                      const SizedBox(height: 16),
                      _ReviewBanner(rso: rso),
                    ],
                    const SizedBox(height: 20),
                    SectionLabel(text: 'About'),
                    const SizedBox(height: 8),
                    Text(
                      rso.description,
                      style: AppTheme.body(
                        size: 14,
                        color: AppColors.bodyForeground,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in rso.tags)
                          StaticChip.tinted(label: tag, color: rso.color),
                      ],
                    ),
                    if (detail == null) ...[
                      if (_error case final error?)
                        ErrorBlock(message: error, onRetry: _load)
                      else
                        const LoadingBlock(),
                    ] else ...[
                      _InfoSection(rso: detail),
                      if (detail.isAdmin) ...[
                        const SizedBox(height: 20),
                        _LeaderTools(
                          rso: detail,
                          onUpdated: (updated) =>
                              setState(() => _detail = updated),
                          onEventCreated: _load,
                        ),
                      ],
                      if (detail.upcomingEvents.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        SectionLabel(text: 'Upcoming Events'),
                        const SizedBox(height: 12),
                        for (final event in detail.upcomingEvents) ...[
                          _DetailEventRow(event: event),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                    const SizedBox(height: 12),
                    SectionLabel(text: 'Members'),
                    const SizedBox(height: 12),
                    _MemberStack(rso: rso, members: members),
                    // Clears the pinned CTA and the shell's navigation bar.
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ],
          ),
          // Nobody joins a proposal until Student Affairs approves it.
          if (rso.isApproved)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _JoinCta(
                rso: rso,
                joined: joined,
                entryPoint: widget.entryPoint,
                recRequestId: widget.recRequestId,
              ),
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.rso, required this.saved});

  final Rso rso;
  final bool saved;

  Future<void> _toggleSave(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().toggleSave(rso, source: 'group_detail');
    } on ApiException catch (e) {
      if (context.mounted) {
        reportError(context, e, screen: Screens.groupDetail);
      }
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: Stack(
        fit: StackFit.expand,
        children: [
          OrgImage(rso: rso, iconSize: 56),
          // Darkens the lower half so the name stays legible over any photo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66080D28), Color(0xF2171A21)],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: kPageGutter,
            child: RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              background: AppColors.background.withValues(alpha: 0.6),
              size: 36,
              iconSize: 17,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: 12,
            right: kPageGutter,
            child: RoundIconButton(
              icon: saved
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              tooltip: saved ? 'Remove from saved' : 'Save',
              background: AppColors.background.withValues(alpha: 0.6),
              foreground: saved ? AppColors.primary : AppColors.foreground,
              size: 36,
              iconSize: 17,
              onPressed: () => _toggleSave(context),
            ),
          ),
          if (rso.verified)
            const Positioned(
              top: 20,
              right: kPageGutter + 44,
              child: OfficialBadge(label: 'Official RSO'),
            ),
          Positioned(
            left: kPageGutter,
            right: kPageGutter,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rso.category.label.toUpperCase(),
                  style: AppTheme.body(
                    size: 11,
                    weight: FontWeight.w800,
                    color: AppColors.accent.withValues(alpha: 0.75),
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(rso.name, style: AppTheme.heading(size: 24, height: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.rso,
    required this.members,
    required this.detail,
  });

  final Rso rso;
  final int members;

  /// The full profile, once loaded. Its stats show a dash until then.
  final Rso? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: StatTile(
            value: '$members',
            label: 'Members',
            color: rso.color,
          ),
        ),
        Expanded(
          child: StatTile(
            value: detail == null ? '–' : '${detail!.upcomingEvents.length}',
            label: 'Upcoming',
            color: AppColors.accent,
          ),
        ),
        Expanded(
          child: StatTile(
            value: '${detail?.foundedYear ?? '–'}',
            label: 'Founded',
            color: AppColors.teal,
          ),
        ),
      ],
    );
  }
}

/// Where the group meets and how to reach it, for whatever the group filled
/// in.
class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.rso});

  final Rso rso;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (rso.meetingBuilding case final building?)
        (Icons.location_on_outlined, 'Meets at $building'),
      if (rso.contactEmail case final email?)
        (Icons.mail_outline_rounded, email),
      if (rso.instagramUrl case final url?) (Icons.camera_alt_outlined, url),
      if (rso.websiteUrl case final url?) (Icons.language_rounded, url),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(text: 'Details'),
          const SizedBox(height: 10),
          for (final (icon, text) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.mutedForeground),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.bodyForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailEventRow extends StatelessWidget {
  const _DetailEventRow({required this.event});

  final CampusEvent event;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      border: Colors.transparent,
      onTap: () => Navigator.of(context).push(
        EventDetailScreen.route(
          event.id,
          entryPoint: EventEntryPoint.groupDetail,
          preview: event,
        ),
      ),
      child: Row(
        children: [
          const TintedIconTile(
            icon: Icons.calendar_today_rounded,
            color: AppColors.accent,
            size: 40,
            iconSize: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  event.title,
                  style: AppTheme.body(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.date} · ${event.time} · ${event.location}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The overlapping avatar row. Initials stand in until member photos exist.
class _MemberStack extends StatelessWidget {
  const _MemberStack({required this.rso, required this.members});

  final Rso rso;
  final int members;

  static const _initials = ['MR', 'JC', 'AP', 'DB', 'LG'];

  @override
  Widget build(BuildContext context) {
    final colors = [
      rso.color,
      AppColors.accent,
      AppColors.teal,
      AppColors.orange,
      AppColors.violet,
    ];
    final shown = _initials.take(members).toList();
    if (shown.isEmpty) {
      return Text(
        'Be the first to join.',
        style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
      );
    }

    const diameter = 36.0;
    const step = 28.0; // 8px of overlap between neighbours.

    return Row(
      children: [
        SizedBox(
          width: (shown.length - 1) * step + diameter,
          height: diameter,
          child: Stack(
            // Painted back-to-front, so reversing puts the first avatar on top
            // and each one overlaps the avatar to its right.
            children: [
              for (final (index, initials) in shown.indexed.toList().reversed)
                Positioned(
                  left: index * step,
                  child: Container(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      color: colors[index],
                      shape: BoxShape.circle,
                      // Cuts this avatar out of the one behind it.
                      border: Border.all(color: AppColors.background, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: AppTheme.body(
                        size: 11,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (members > shown.length) ...[
          const SizedBox(width: 12),
          Text(
            '+${members - shown.length} more',
            style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
          ),
        ],
      ],
    );
  }
}

class _JoinCta extends StatefulWidget {
  const _JoinCta({
    required this.rso,
    required this.joined,
    required this.entryPoint,
    this.recRequestId,
  });

  final Rso rso;
  final bool joined;
  final EntryPoint entryPoint;
  final String? recRequestId;

  @override
  State<_JoinCta> createState() => _JoinCtaState();
}

class _JoinCtaState extends State<_JoinCta> {
  /// Joining goes through the form (BQ7), which reports its own progress and
  /// errors.
  Future<void> _join() async {
    final messenger = ScaffoldMessenger.of(context);
    final joined = await JoinFormSheet.show(
      context,
      rso: widget.rso,
      entryPoint: widget.entryPoint,
      recRequestId: widget.recRequestId,
    );
    if (joined ?? false) {
      messenger.showSnackBar(
        SnackBar(content: Text('Welcome to ${widget.rso.name}!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final joined = widget.joined;

    return DecoratedBox(
      // Fades the list out behind the button instead of cutting it off.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.background,
            AppColors.background,
            Colors.transparent,
          ],
          stops: [0, 0.7, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 16),
        child: Material(
          color: joined ? AppColors.secondary : widget.rso.color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: joined ? null : _join,
            child: Container(
              width: double.infinity,
              height: 54,
              alignment: Alignment.center,
              child: Text(
                joined ? '✓ Joined - Welcome!' : 'Join RSO',
                style: AppTheme.heading(
                  size: 16,
                  weight: FontWeight.w700,
                  color: joined ? AppColors.mutedForeground : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A proposal's standing, shown to its creator (no one else can see it).
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.rso});

  final Rso rso;

  @override
  Widget build(BuildContext context) {
    final pending = rso.reviewStatus == ReviewStatus.pending;
    final color = pending ? AppColors.accent : AppColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: pending ? 0.08 : 0.18),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            pending ? Icons.hourglass_top_rounded : Icons.block_rounded,
            size: 18,
            color: pending ? AppColors.accent : AppColors.foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pending
                  ? 'Pending review. Only you can see this group until '
                        'Student Affairs approves it.'
                  : 'Not approved: '
                        '${rso.rejectionReason ?? 'no reason given'}',
              style: AppTheme.body(
                size: 13,
                height: 1.45,
                weight: FontWeight.w600,
                color: pending ? AppColors.accent : AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderTools extends StatefulWidget {
  const _LeaderTools({
    required this.rso,
    required this.onUpdated,
    required this.onEventCreated,
  });

  final Rso rso;
  final ValueChanged<Rso> onUpdated;
  final VoidCallback onEventCreated;

  @override
  State<_LeaderTools> createState() => _LeaderToolsState();
}

class _LeaderToolsState extends State<_LeaderTools> {
  bool _uploading = false;

  Future<void> _createEvent() async {
    final created = await Navigator.of(
      context,
    ).push(CreateEventScreen.route(widget.rso));
    if (created != null && mounted) widget.onEventCreated();
  }

  Future<void> _changePhoto() async {
    final services = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    final photos = services.photos;
    if (!photos.enabled) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Photo uploads need Firebase (AUTH_MODE=firebase).'),
        ),
      );
      return;
    }
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      backgroundColor: AppColors.background,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera_rounded,
                color: AppColors.accent,
              ),
              title: Text('Take a photo', style: AppTheme.body(size: 14)),
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.accent,
              ),
              title: Text(
                'Choose from gallery',
                style: AppTheme.body(size: 14),
              ),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await photos.pick(source);
      if (bytes == null) return;
      final url = await photos.uploadGroupCover(widget.rso.id, bytes);
      final updated = await services.groups.updateImage(widget.rso.id, url);
      widget.onUpdated(updated);
      messenger.showSnackBar(
        const SnackBar(content: Text('Cover photo updated.')),
      );
    } on PhotoUploadException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ApiException catch (e) {
      if (mounted) reportError(context, e, screen: Screens.groupDetail);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(text: 'You lead this group'),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Create event',
          onPressed: widget.rso.isApproved ? _createEvent : null,
        ),
        const SizedBox(height: 10),
        PrimaryButton.secondary(
          label: 'Change cover photo',
          busy: _uploading,
          onPressed: _changePhoto,
        ),
      ],
    );
  }
}
