import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/ids.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/rso.dart';
import '../../state/app_state.dart';
import '../shell/track_screen.dart';

/// The join form: the step between "Join RSO" and being a member.
///
/// It is its own step so BQ7 can see where students give up: on the profile,
/// on the form, or never submitting it. Opening it records
/// `join_form_opened` with a new attempt id; submitting sends the same id.
class JoinFormSheet extends StatefulWidget {
  const JoinFormSheet({
    super.key,
    required this.rso,
    required this.entryPoint,
    this.recRequestId,
  });

  final Rso rso;
  final EntryPoint entryPoint;
  final String? recRequestId;

  /// True once the student joined; null if they closed the form.
  static Future<bool?> show(
    BuildContext context, {
    required Rso rso,
    required EntryPoint entryPoint,
    String? recRequestId,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
    ),
    builder: (_) => JoinFormSheet(
      rso: rso,
      entryPoint: entryPoint,
      recRequestId: recRequestId,
    ),
  );

  /// The backend keeps up to this many characters of the note.
  static const maxMotivation = 500;

  @override
  State<JoinFormSheet> createState() => _JoinFormSheetState();
}

class _JoinFormSheetState extends State<JoinFormSheet> {
  final _attemptId = newUuid();
  final _motivation = TextEditingController();

  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AppServices>().analytics.joinFormOpened(
      groupId: widget.rso.id,
      joinAttemptId: _attemptId,
    );
  }

  @override
  void dispose() {
    _motivation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    final note = _motivation.text.trim();
    try {
      await context.read<AppState>().join(
        widget.rso,
        entryPoint: widget.entryPoint,
        recRequestId: widget.recRequestId,
        joinAttemptId: _attemptId,
        motivation: note.isEmpty ? null : note,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.joinForm);
      setState(() {
        _sending = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TrackScreen(
      name: Screens.joinForm,
      child: Padding(
        // Keeps the note above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(kPageGutter, 24, kPageGutter, 16),
          children: [
            Text(
              'Join ${widget.rso.name}',
              style: AppTheme.heading(size: 20, height: 1.2),
            ),
            const SizedBox(height: 4),
            Text(
              "You'll get its events and group messages.",
              style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 20),
            const SectionLabel(text: 'A note for the organizers (optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _motivation,
              maxLines: 4,
              maxLength: JoinFormSheet.maxMotivation,
              textCapitalization: TextCapitalization.sentences,
              style: AppTheme.body(size: 14),
              decoration: const InputDecoration(
                hintText: 'What brings you to the group?',
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: AppTheme.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Join',
              busy: _sending,
              color: widget.rso.color,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            PrimaryButton.secondary(
              label: 'Not now',
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
