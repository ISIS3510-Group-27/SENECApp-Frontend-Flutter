import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/offline.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/event_draft.dart';
import '../../data/models/catalog.dart';
import '../../data/models/leader_insights.dart';
import '../../data/models/rso.dart';
import '../../data/repositories/groups_repository.dart';
import '../shell/track_screen.dart';
import 'event_draft_view_model.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key, required this.rso});

  final Rso rso;

  static const minTitle = 3;
  static const lengths = [
    Duration(hours: 1),
    Duration(minutes: 90),
    Duration(hours: 2),
    Duration(hours: 3),
  ];

  static Route<CampusEvent> route(Rso rso) => MaterialPageRoute<CampusEvent>(
    builder: (_) => CreateEventScreen(rso: rso),
  );

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _title = TextEditingController();
  final _room = TextEditingController();
  final _capacity = TextEditingController();
  final _description = TextEditingController();

  DateTime? _date;
  TimeOfDay? _start;
  Duration _length = const Duration(hours: 2);
  int? _buildingId;

  late final Future<List<Building>> _buildings = context
      .read<AppServices>()
      .catalog
      .buildings();
  late Future<BestTimes> _bestTimes = _loadBestTimes();
  late final Future<Audience> _audience = context
      .read<AppServices>()
      .groups
      .audience(widget.rso.id);

  SuggestedSlot? _pickedSlot;
  late final EventDraftViewModel _drafts;
  bool _leaving = false;
  bool _leaveDialogOpen = false;

  @override
  void initState() {
    super.initState();
    final services = context.read<AppServices>();
    final session = services.offline.sessionVersion;
    _drafts = EventDraftViewModel(
      groupId: widget.rso.id,
      auth: services.auth,
      store: services.eventDrafts,
      events: services.events,
      analytics: services.analytics,
      isOnline: () => mounted && isOnline(context, listen: false),
      sessionActive: () => services.offline.sessionVersion == session,
    )..addListener(_draftChanged);
    _restoreDraft();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  EventDraft get _form => EventDraft(
    title: _title.text,
    room: _room.text,
    capacity: _capacity.text,
    description: _description.text,
    date: _date,
    startMinute: _start == null ? null : _start!.hour * 60 + _start!.minute,
    durationMinutes: _length.inMinutes,
    buildingId: _buildingId,
  );

  Future<void> _restoreDraft() async {
    await _drafts.load();
    if (!mounted || !_drafts.ready) return;
    _fillForm(_drafts.saved ?? const EventDraft());
  }

  void _fillForm(EventDraft draft) => setState(() {
    _title.text = draft.title;
    _room.text = draft.room;
    _capacity.text = draft.capacity;
    _description.text = draft.description;
    _date = draft.date;
    final minute = draft.startMinute;
    _start = minute == null
        ? null
        : TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
    _length = Duration(minutes: draft.durationMinutes);
    _buildingId = draft.buildingId;
    _pickedSlot = null;
  });

  Future<BestTimes> _loadBestTimes() => context
      .read<AppServices>()
      .groups
      .bestTimes(widget.rso.id, length: _length);

  DateTime? get _startsAt {
    final date = _date;
    final start = _start;
    if (date == null || start == null) return null;
    return DateTime(date.year, date.month, date.day, start.hour, start.minute);
  }

  bool get _canPublish {
    return _drafts.ready &&
        !_drafts.busy &&
        !_drafts.needsReview &&
        !_drafts.alreadyPublished &&
        _form.canPublish(DateTime.now());
  }

  @override
  void dispose() {
    _drafts.removeListener(_draftChanged);
    _drafts.dispose();
    _title.dispose();
    _room.dispose();
    _capacity.dispose();
    _description.dispose();
    super.dispose();
  }

  void _setLength(Duration length) {
    if (length == _length) return;
    setState(() {
      _length = length;
      _pickedSlot = null;
      _bestTimes = _loadBestTimes();
    });
  }

  void _useSlot(SuggestedSlot slot) {
    final local = slot.nextStartsAt.toLocal();
    setState(() {
      _pickedSlot = slot;
      _date = DateUtils.dateOnly(local);
      _start = TimeOfDay.fromDateTime(local);
      _length = slot.length;
    });
  }

  void _useAudienceCell(AudienceCell cell) {
    setState(() {
      _pickedSlot = null;
      if (cell.building case final building?) _buildingId = building.id;
      if (cell.hour case final hour?) {
        _start = TimeOfDay(hour: hour, minute: 0);
        _date ??= _nextDateAt(hour);
      }
    });
  }

  DateTime _nextDateAt(int hour) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    return now.hour < hour - 1 ? today : today.add(const Duration(days: 1));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date == null || _date!.isBefore(DateUtils.dateOnly(now))
          ? now
          : _date!,
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _pickedSlot = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _start ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null) {
      setState(() {
        _start = picked;
        _pickedSlot = null;
      });
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    FocusScope.of(context).unfocus();
    final event = await _drafts.publish(_form);
    if (!mounted) return;
    if (event != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event published. Members were notified.'),
        ),
      );
      setState(() => _leaving = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop(event);
    } else if (_drafts.error == null && !_drafts.needsReview) {
      _savedMessage();
    }
  }

  void _savedMessage() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Draft saved on this device. Not published.')),
  );

  Future<void> _saveDraft() async {
    if (await _drafts.save(_form) && mounted) _savedMessage();
  }

  Future<void> _leave() async {
    if (_drafts.busy || _leaveDialogOpen) return;
    if (!_drafts.hasChanges(_form)) {
      Navigator.of(context).pop();
      return;
    }
    _leaveDialogOpen = true;
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Save your draft?', style: AppTheme.heading(size: 18)),
        content: Text(
          'Some edits are not saved on this device.',
          style: AppTheme.body(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'leave'),
            child: const Text('Leave without saving'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );
    _leaveDialogOpen = false;
    if (!mounted || decision == null || decision == 'stay') return;
    if (decision == 'save' && !await _drafts.save(_form)) return;
    if (!mounted) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discardDraft() async {
    final discard = await _confirm(
      'Delete this draft?',
      'This removes the saved draft and current edits from this device. '
          'It does not delete any published event.',
      'Delete draft',
    );
    if (discard && await _drafts.discard() && mounted) {
      _fillForm(const EventDraft());
    }
  }

  Future<void> _allowRetry() async {
    final retry = await _confirm(
      'Did you check the group events?',
      'The last request may have published the event. Only allow another '
          'attempt after checking that it is not already listed.',
      'Not published: allow retry',
    );
    if (retry) await _drafts.allowRetry();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(title, style: AppTheme.heading(size: 18)),
          content: Text(message, style: AppTheme.body(size: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) =>
      TrackScreen(name: Screens.createEvent, child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final online = isOnline(context);
    if (_drafts.loading || !_drafts.ready) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: _drafts.loading
                    ? const LoadingBlock()
                    : ErrorBlock(
                        message: _drafts.error ?? 'Draft unavailable.',
                        onRetry: _restoreDraft,
                      ),
              ),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: _leaving || (!_drafts.busy && !_drafts.hasChanges(_form)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _drafts.busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                12,
                kPageGutter,
                40,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    size: 36,
                    iconSize: 17,
                    onPressed: _leave,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.rso.name.toUpperCase(),
                  style: AppTheme.body(
                    size: 11,
                    weight: FontWeight.w800,
                    color: widget.rso.color,
                    letterSpacing: 1.6,
                  ),
                ),
                Text('New event', style: AppTheme.heading(size: 26)),
                if (!online) ...[
                  const SizedBox(height: 12),
                  const OfflineNote(
                    'Offline. Drafts stay on this device; publishing waits for a connection.',
                  ),
                ],
                if (_drafts.saved != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _drafts.needsReview
                              ? 'Publication not confirmed'
                              : _drafts.alreadyPublished
                              ? 'Event already published'
                              : _drafts.hasChanges(_form)
                              ? 'Draft has unsaved edits'
                              : 'Draft saved on this device',
                          style: AppTheme.body(size: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete draft',
                        onPressed: _discardDraft,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ],
                if (_drafts.needsReview) ...[
                  Text(
                    'Check the group events before retrying. The last request may have succeeded.',
                    style: AppTheme.body(size: 13, color: AppColors.orange),
                  ),
                  TextButton(
                    onPressed: online ? _allowRetry : null,
                    child: const Text('Review publication'),
                  ),
                ],
                const SizedBox(height: 24),
                const SectionLabel(text: 'Your members can make it'),
                const SizedBox(height: 10),
                _BestTimesSection(
                  groupId: widget.rso.id,
                  bestTimes: _bestTimes,
                  picked: _pickedSlot,
                  onUse: _useSlot,
                  onRetry: () => setState(() => _bestTimes = _loadBestTimes()),
                ),
                const SizedBox(height: 24),
                const SectionLabel(text: 'Where students engage'),
                const SizedBox(height: 10),
                _AudienceSection(
                  groupId: widget.rso.id,
                  audience: _audience,
                  onUse: _useAudienceCell,
                ),
                const SizedBox(height: 28),
                const SectionLabel(text: 'Title'),
                const SizedBox(height: 10),
                TextField(
                  controller: _title,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTheme.body(size: 14),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Doubles night',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                const SectionLabel(text: 'When'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _PickerField(
                        icon: Icons.calendar_today_rounded,
                        text: _date == null ? 'Pick a date' : Dates.day(_date!),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PickerField(
                        icon: Icons.schedule_rounded,
                        text: _start == null
                            ? 'Start time'
                            : Dates.time(_startsAt ?? _todayAt(_start!)),
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final length in CreateEventScreen.lengths)
                      SelectableChip.filter(
                        label: _lengthLabel(length),
                        selected: length == _length,
                        onSelected: (_) => _setLength(length),
                      ),
                  ],
                ),
                if (_startsAt case final startsAt?)
                  if (!startsAt.isAfter(DateTime.now()))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Pick a time in the future.',
                        style: AppTheme.body(size: 12, color: AppColors.orange),
                      ),
                    ),
                const SizedBox(height: 20),
                const SectionLabel(text: 'Where'),
                const SizedBox(height: 10),
                FutureBuilder<List<Building>>(
                  future: _buildings,
                  builder: (context, snapshot) {
                    final buildings = snapshot.data ?? const <Building>[];
                    final known = buildings.any((b) => b.id == _buildingId);
                    return DropdownButtonFormField<int>(
                      initialValue: _buildingId,
                      key: ValueKey(
                        'building-$_buildingId-${buildings.length}',
                      ),
                      isExpanded: true,
                      dropdownColor: AppColors.card,
                      hint: Text(
                        snapshot.hasError
                            ? 'Buildings unavailable'
                            : 'Building',
                        style: AppTheme.body(
                          size: 14,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      items: [
                        if (!known && _buildingId != null)
                          DropdownMenuItem(
                            value: _buildingId,
                            child: Text(
                              'Saved building #$_buildingId',
                              style: AppTheme.body(size: 14),
                            ),
                          ),
                        for (final building in buildings)
                          DropdownMenuItem(
                            value: building.id,
                            child: Text(
                              building.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.body(size: 14),
                            ),
                          ),
                      ],
                      onChanged: (id) => setState(() => _buildingId = id),
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _room,
                  maxLength: 200,
                  style: AppTheme.body(size: 14),
                  decoration: const InputDecoration(
                    hintText: 'Room or spot, e.g. Salón 224',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                const SectionLabel(text: 'Capacity (optional)'),
                const SizedBox(height: 10),
                TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTheme.body(size: 14),
                  decoration: const InputDecoration(hintText: 'No limit'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                const SectionLabel(text: 'Description (optional)'),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTheme.body(size: 14),
                  decoration: const InputDecoration(
                    hintText: 'What will happen, what to bring...',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_drafts.error case final error?) ...[
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: AppTheme.body(size: 13, color: AppColors.orange),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: AppColors.foreground,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    textStyle: AppTheme.heading(
                      size: 16,
                      weight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_drafts.busy ? 'Saving...' : 'Save draft'),
                  onPressed: _drafts.busy || _drafts.alreadyPublished
                      ? null
                      : _saveDraft,
                ),
                const SizedBox(height: 10),
                PrimaryButton(
                  label: 'Publish event',
                  busy: _drafts.busy,
                  onPressed: online && _canPublish ? _publish : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static DateTime _todayAt(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  static String _lengthLabel(Duration length) {
    final hours = length.inMinutes / 60;
    return hours == hours.roundToDouble()
        ? '${hours.round()} h'
        : '${hours.toStringAsFixed(1)} h';
  }
}

class _BestTimesSection extends StatelessWidget {
  const _BestTimesSection({
    required this.groupId,
    required this.bestTimes,
    required this.picked,
    required this.onUse,
    required this.onRetry,
  });

  final int groupId;
  final Future<BestTimes> bestTimes;
  final SuggestedSlot? picked;
  final ValueChanged<SuggestedSlot> onUse;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BestTimes>(
      future: bestTimes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snapshot.hasError) {
          return _Note(
            text: _errorText(snapshot.error),
            actionLabel: 'Retry',
            onAction: onRetry,
          );
        }
        final data = snapshot.data!;
        if (data.slots.isEmpty) {
          return _Note(
            text: data.membersWithSchedule == 0
                ? 'None of your members has added a class schedule yet, so '
                      "there's nothing to compare."
                : 'No time works for anyone at this length. Try a shorter '
                      'event.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SavedCopyNote(
              dataKeys: [GroupsRepository.bestTimesKey(groupId)],
              message: "Suggestions come back up to date when you're online.",
              padding: const EdgeInsets.only(bottom: 10),
            ),
            Text(
              'Based on the schedules of ${data.membersWithSchedule} of '
              '${data.members} members'
              '${data.pastEvents > 0 ? ' and ${data.pastEvents} past events' : ''}.',
              style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 10),
            for (final slot in data.slots) ...[
              _SlotCard(
                slot: slot,
                total: data.membersWithSchedule,
                picked: identical(slot, picked),
                onUse: () => onUse(slot),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.total,
    required this.picked,
    required this.onUse,
  });

  final SuggestedSlot slot;
  final int total;
  final bool picked;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final starts = slot.nextStartsAt;
    final attendance = slot.attendanceRate;
    return AppCard(
      onTap: onUse,
      border: picked ? AppColors.accent : AppColors.border,
      child: Row(
        children: [
          TintedIconTile(
            icon: picked ? Icons.check_rounded : Icons.groups_rounded,
            color: AppColors.teal,
            size: 40,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Dates.day(starts)} · ${Dates.time(starts)} - '
                  '${Dates.time(starts.add(slot.length))}',
                  style: AppTheme.heading(size: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '${slot.freeMembers} of $total members free'
                  '${attendance == null ? '' : ' · past events ${(attendance * 100).round()}% full'}',
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.bodyForeground,
                  ),
                ),
              ],
            ),
          ),
          Text(
            picked ? 'Picked' : 'Use',
            style: AppTheme.body(
              size: 13,
              weight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudienceSection extends StatelessWidget {
  const _AudienceSection({
    required this.groupId,
    required this.audience,
    required this.onUse,
  });

  final int groupId;
  final Future<Audience> audience;
  final ValueChanged<AudienceCell> onUse;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Audience>(
      future: audience,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snapshot.hasError) return _Note(text: _errorText(snapshot.error));
        final data = snapshot.data!;
        if (data.isEmpty) {
          return const _Note(
            text:
                'Not enough activity on campus yet to tell where students '
                'engage.',
          );
        }
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SavedCopyNote(
                dataKeys: [GroupsRepository.audienceKey(groupId)],
                message: "Numbers update when you're online.",
                padding: const EdgeInsets.only(bottom: 10),
              ),
              Text(
                data.answer,
                style: AppTheme.body(
                  size: 13,
                  height: 1.45,
                  color: AppColors.bodyForeground,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cell in [
                    ...data.bestTimeAndPlace.take(3),
                    if (data.bestTimeAndPlace.isEmpty)
                      ...data.byBuilding.take(3),
                  ])
                    ActionChip(
                      backgroundColor: AppColors.secondary,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      avatar: const Icon(
                        Icons.place_rounded,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      label: Text(
                        _cellLabel(cell),
                        style: AppTheme.body(size: 12, weight: FontWeight.w700),
                      ),
                      onPressed: () => onUse(cell),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tap one to use its time and building.',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _cellLabel(AudienceCell cell) {
    final parts = [
      if (cell.hour case final hour?) _hourLabel(hour),
      if (cell.building case final building?) building.code,
      if (cell.interactionRate case final rate?) '${(rate * 100).round()}%',
    ];
    return parts.join(' · ');
  }

  static String _hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'AM' : 'PM'}';
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(size: 14, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.accent,
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                size: 13,
                height: 1.4,
                color: AppColors.bodyForeground,
              ),
            ),
          ),
          if (actionLabel case final label?)
            TextButton(
              onPressed: onAction,
              child: Text(
                label,
                style: AppTheme.body(
                  size: 13,
                  weight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _errorText(Object? error) =>
    error is ApiException ? error.message : 'Something went wrong.';
