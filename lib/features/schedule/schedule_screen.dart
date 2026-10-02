import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/catalog.dart';
import '../../data/models/schedule_block.dart';
import '../../data/repositories/catalog_repository.dart';
import '../shell/track_screen.dart';

/// The student's weekly classes.
///
/// "Free right now" reads the gaps between them, and the building of the
/// class before or after a gap stands in for the student's location when GPS
/// is off. Edits stay local until "Save", which replaces the whole schedule.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ScheduleScreen());

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<ScheduleBlock>? _blocks;
  String? _error;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final blocks = await context.read<AppServices>().me.schedule();
      if (mounted) setState(() => _blocks = _sorted(blocks));
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.schedule);
      setState(() => _error = e.message);
    }
  }

  static List<ScheduleBlock> _sorted(Iterable<ScheduleBlock> blocks) =>
      blocks.toList()..sort(
        (a, b) => a.weekday != b.weekday
            ? a.weekday.compareTo(b.weekday)
            : ScheduleBlock.minutesOf(
                a.start,
              ).compareTo(ScheduleBlock.minutesOf(b.start)),
      );

  /// Opens the class sheet to add a class, or to edit [existing].
  Future<void> _edit([ScheduleBlock? existing]) async {
    final others = [...?_blocks]..remove(existing);
    final result = await _ClassSheet.show(
      context,
      initial: existing,
      others: others,
      catalog: context.read<AppServices>().catalog,
    );
    if (result == null || !mounted) return;
    setState(() {
      _blocks = _sorted([...others, result]);
      _dirty = true;
    });
  }

  void _remove(ScheduleBlock block) => setState(() {
    _blocks = [...?_blocks]..remove(block);
    _dirty = true;
  });

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await context.read<AppServices>().me.saveSchedule(_blocks!);
      if (!mounted) return;
      setState(() {
        _blocks = _sorted(saved);
        _dirty = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Schedule saved.')));
    } on ApiException catch (e) {
      if (mounted) reportError(context, e, screen: Screens.schedule);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Discard changes?', style: AppTheme.heading(size: 18)),
        content: Text(
          "Your schedule edits haven't been saved.",
          style: AppTheme.body(size: 14, color: AppColors.bodyForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.schedule,
    ready: _blocks != null || _error != null,
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final blocks = _blocks;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kPageGutter,
                  12,
                  kPageGutter,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      size: 36,
                      iconSize: 17,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Class schedule',
                            style: AppTheme.heading(size: 20),
                          ),
                          Text(
                            'We suggest events in the gaps between your '
                            'classes.',
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
              ),
              Expanded(
                child: blocks == null
                    ? (_error == null
                          ? const LoadingBlock()
                          : ErrorBlock(message: _error!, onRetry: _load))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          kPageGutter,
                          20,
                          kPageGutter,
                          20,
                        ),
                        children: [
                          if (blocks.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Text(
                                'No classes yet. Add the ones you have each '
                                'week.',
                                textAlign: TextAlign.center,
                                style: AppTheme.body(
                                  size: 13,
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ),
                          for (final (day, name)
                              in ScheduleBlock.weekdayNames.indexed)
                            if (blocks.any((b) => b.weekday == day)) ...[
                              SectionLabel(text: name),
                              const SizedBox(height: 10),
                              for (final block in blocks.where(
                                (b) => b.weekday == day,
                              )) ...[
                                _ClassRow(
                                  block: block,
                                  onTap: () => _edit(block),
                                  onRemove: () => _remove(block),
                                ),
                                const SizedBox(height: 8),
                              ],
                              const SizedBox(height: 12),
                            ],
                          PrimaryButton.secondary(
                            label: '+ Add class',
                            onPressed: _saving ? null : _edit,
                          ),
                        ],
                      ),
              ),
              if (blocks != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPageGutter,
                    8,
                    kPageGutter,
                    16,
                  ),
                  child: PrimaryButton(
                    label: 'Save schedule',
                    busy: _saving,
                    onPressed: _dirty ? _save : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({
    required this.block,
    required this.onTap,
    required this.onRemove,
  });

  final ScheduleBlock block;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final details = [?block.title, ?block.buildingName].join(' · ');

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${block.start.format(context)} - '
                  '${block.end.format(context)}',
                  style: AppTheme.heading(size: 14),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: AppColors.mutedForeground,
            tooltip: 'Remove class',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Adds or edits one class: day, times, name and building.
class _ClassSheet extends StatefulWidget {
  const _ClassSheet({
    required this.initial,
    required this.others,
    required this.catalog,
  });

  final ScheduleBlock? initial;

  /// The rest of the schedule, to catch overlaps before saving.
  final List<ScheduleBlock> others;

  final CatalogRepository catalog;

  static Future<ScheduleBlock?> show(
    BuildContext context, {
    required ScheduleBlock? initial,
    required List<ScheduleBlock> others,
    required CatalogRepository catalog,
  }) => showModalBottomSheet<ScheduleBlock>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
    ),
    builder: (_) =>
        _ClassSheet(initial: initial, others: others, catalog: catalog),
  );

  @override
  State<_ClassSheet> createState() => _ClassSheetState();
}

class _ClassSheetState extends State<_ClassSheet> {
  static const _shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late int _weekday = widget.initial?.weekday ?? 0;
  late TimeOfDay _start =
      widget.initial?.start ?? const TimeOfDay(hour: 8, minute: 30);
  late TimeOfDay _end =
      widget.initial?.end ?? const TimeOfDay(hour: 9, minute: 50);
  late final _title = TextEditingController(text: widget.initial?.title);
  late int? _buildingId = widget.initial?.buildingId;
  late final Future<List<Building>> _buildings = widget.catalog.buildings();
  String? _problem;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _done() async {
    final buildings = await _buildings.catchError((_) => <Building>[]);
    final block = ScheduleBlock(
      weekday: _weekday,
      start: _start,
      end: _end,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      buildingId: _buildingId,
      buildingName: buildings
          .where((b) => b.id == _buildingId)
          .firstOrNull
          ?.name,
    );
    if (ScheduleBlock.minutesOf(_end) <= ScheduleBlock.minutesOf(_start)) {
      setState(() => _problem = 'The class has to end after it starts.');
    } else if (widget.others.any(block.overlaps)) {
      setState(() => _problem = 'That overlaps another class that day.');
    } else if (mounted) {
      Navigator.of(context).pop(block);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the name field above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 16),
        children: [
          Text(
            widget.initial == null ? 'Add class' : 'Edit class',
            style: AppTheme.heading(size: 20),
          ),
          const SizedBox(height: 16),
          const SectionLabel(text: 'Day'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (day, label) in _shortDays.indexed)
                SelectableChip.filter(
                  label: label,
                  selected: _weekday == day,
                  onSelected: (_) => setState(() => _weekday = day),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'Starts',
                  time: _start,
                  onPressed: () => _pickTime(start: true),
                ),
              ),
              Expanded(
                child: _TimeButton(
                  label: 'Ends',
                  time: _end,
                  onPressed: () => _pickTime(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionLabel(text: 'Class name (optional)'),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            style: AppTheme.body(size: 14),
            decoration: const InputDecoration(hintText: 'e.g. Cálculo II'),
          ),
          const SizedBox(height: 16),
          const SectionLabel(text: 'Building (optional)'),
          const SizedBox(height: 10),
          FutureBuilder(
            future: _buildings,
            builder: (context, snapshot) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final building in snapshot.data ?? const <Building>[])
                  SelectableChip.filter(
                    label: building.code,
                    selected: _buildingId == building.id,
                    onSelected: (on) =>
                        setState(() => _buildingId = on ? building.id : null),
                  ),
              ],
            ),
          ),
          if (_problem case final problem?) ...[
            const SizedBox(height: 16),
            Text(
              problem,
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: widget.initial == null ? 'Add class' : 'Done',
            onPressed: _done,
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPressed,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTheme.sectionLabel),
          const SizedBox(height: 2),
          Text(time.format(context), style: AppTheme.heading(size: 16)),
        ],
      ),
    );
  }
}
