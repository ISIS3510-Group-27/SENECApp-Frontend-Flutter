import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/format/dates.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/catalog.dart';
import '../../data/models/leader_insights.dart';
import '../../data/models/rso.dart';
import '../shell/track_screen.dart';

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
  bool _publishing = false;
  String? _error;

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
    final startsAt = _startsAt;
    return _title.text.trim().length >= CreateEventScreen.minTitle &&
        startsAt != null &&
        startsAt.isAfter(DateTime.now()) &&
        _capacityValue != -1;
  }

  int? get _capacityValue {
    final text = _capacity.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    return value == null || value < 1 ? -1 : value;
  }

  @override
  void dispose() {
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
      initialDate: _date ?? now,
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
    final startsAt = _startsAt;
    if (!_canPublish || startsAt == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _publishing = true;
      _error = null;
    });
    final room = _room.text.trim();
    final description = _description.text.trim();
    try {
      final event = await context.read<AppServices>().events.create(
        widget.rso.id,
        title: _title.text.trim(),
        startsAt: startsAt,
        endsAt: startsAt.add(_length),
        description: description.isEmpty ? null : description,
        buildingId: _buildingId,
        locationDetail: room.isEmpty ? null : room,
        capacity: _capacityValue,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event published. Members were notified.')),
      );
      Navigator.of(context).pop(event);
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.createEvent);
      setState(() {
        _publishing = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      TrackScreen(name: Screens.createEvent, child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 40),
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
            const SizedBox(height: 24),
            const SectionLabel(text: 'Your members can make it'),
            const SizedBox(height: 10),
            _BestTimesSection(
              bestTimes: _bestTimes,
              picked: _pickedSlot,
              onUse: _useSlot,
              onRetry: () => setState(() => _bestTimes = _loadBestTimes()),
            ),
            const SizedBox(height: 24),
            const SectionLabel(text: 'Where students engage'),
            const SizedBox(height: 10),
            _AudienceSection(audience: _audience, onUse: _useAudienceCell),
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
                  initialValue: known ? _buildingId : null,
                  key: ValueKey('building-$_buildingId-${buildings.length}'),
                  isExpanded: true,
                  dropdownColor: AppColors.card,
                  hint: Text(
                    snapshot.hasError ? 'Buildings unavailable' : 'Building',
                    style: AppTheme.body(
                      size: 14,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  items: [
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
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Text(
                error,
                style: AppTheme.body(size: 13, color: AppColors.orange),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Publish event',
              busy: _publishing,
              onPressed: _canPublish ? _publish : null,
            ),
          ],
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
    required this.bestTimes,
    required this.picked,
    required this.onUse,
    required this.onRetry,
  });

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
  const _AudienceSection({required this.audience, required this.onUse});

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
            text: 'Not enough activity on campus yet to tell where students '
                'engage.',
          );
        }
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
