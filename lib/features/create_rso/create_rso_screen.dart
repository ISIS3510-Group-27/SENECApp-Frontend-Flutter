import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/catalog.dart';
import '../../data/models/rso_category.dart';
import '../../state/app_state.dart';
import '../shell/track_screen.dart';

/// The proposal form for a new organization.
///
/// A proposal is created pending: only the student sees it (in My RSOs)
/// until Uniandes Student Affairs approves it, and they're notified either
/// way. Name, category and a description are required; the backend's own
/// minimums are checked as the student types, so "Submit" only lights up
/// for a proposal it will accept.
class CreateRsoScreen extends StatefulWidget {
  const CreateRsoScreen({super.key});

  static const minName = 3;
  static const minDescription = 20;

  /// The backend takes up to this many interest tags.
  static const maxTags = 8;

  @override
  State<CreateRsoScreen> createState() => _CreateRsoScreenState();
}

class _CreateRsoScreenState extends State<CreateRsoScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _descriptionController = TextEditingController();

  RsoCategory? _category;
  final Set<int> _tagIds = {};
  late final Future<List<Interest>> _interests = context
      .read<AppServices>()
      .catalog
      .interests();

  bool _submitting = false;
  String? _error;
  bool _submitted = false;

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String get _name => _nameController.text.trim();
  String get _contact => _contactController.text.trim();
  String get _description => _descriptionController.text.trim();

  bool get _contactValid => _contact.isEmpty || _email.hasMatch(_contact);

  bool get _canSubmit =>
      _name.length >= CreateRsoScreen.minName &&
      _category != null &&
      _description.length >= CreateRsoScreen.minDescription &&
      _contactValid;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _selectCategory(RsoCategory category) => setState(() {
    // Interests belong to a category; ones from the previous pick no longer
    // apply.
    if (category != _category) _tagIds.clear();
    _category = category;
  });

  void _toggleTag(int id) => setState(() {
    if (!_tagIds.remove(id) && _tagIds.length < CreateRsoScreen.maxTags) {
      _tagIds.add(id);
    }
  });

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final appState = context.read<AppState>();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AppServices>().groups.create(
        name: _name,
        categorySlug: _category!.slug,
        description: _description,
        contactEmail: _contact.isEmpty ? null : _contact,
        tagIds: _tagIds,
      );
      if (!mounted) return;
      setState(() => _submitted = true);
      // The pending group shows up in My RSOs.
      appState.refreshMemberships();
    } on ApiException catch (e) {
      if (!mounted) return;
      reportError(context, e, screen: Screens.createGroup);
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      TrackScreen(name: Screens.createGroup, child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      body: _submitted
          ? _Confirmation(
              name: _name,
              onBack: () => Navigator.of(context).pop(),
            )
          : _Form(
              nameController: _nameController,
              contactController: _contactController,
              descriptionController: _descriptionController,
              category: _category,
              interests: _interests,
              tagIds: _tagIds,
              contactValid: _contactValid,
              canSubmit: _canSubmit,
              submitting: _submitting,
              error: _error,
              onCategoryChanged: _selectCategory,
              onTagToggled: _toggleTag,
              // Any keystroke can flip the submit button's state, so the whole
              // form rebuilds on change rather than tracking each field.
              onFieldChanged: () => setState(() {}),
              onSubmit: _submit,
            ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.nameController,
    required this.contactController,
    required this.descriptionController,
    required this.category,
    required this.interests,
    required this.tagIds,
    required this.contactValid,
    required this.canSubmit,
    required this.submitting,
    required this.error,
    required this.onCategoryChanged,
    required this.onTagToggled,
    required this.onFieldChanged,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController contactController;
  final TextEditingController descriptionController;
  final RsoCategory? category;
  final Future<List<Interest>> interests;
  final Set<int> tagIds;
  final bool contactValid;
  final bool canSubmit;
  final bool submitting;
  final String? error;
  final ValueChanged<RsoCategory> onCategoryChanged;
  final ValueChanged<int> onTagToggled;
  final VoidCallback onFieldChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final nameLength = nameController.text.trim().length;
    final descriptionLength = descriptionController.text.trim().length;

    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarClearance),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: Row(
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Create New RSO', style: AppTheme.heading(size: 20)),
                    Text(
                      'Propose a new SENECApp organization',
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
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              'RSO proposals are reviewed by Uniandes Student Affairs via '
              'SENECApp. Approved organizations receive campus resources, '
              'email lists, and official recognition.',
              style: AppTheme.body(
                size: 12,
                height: 1.5,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Field(
          label: 'Organization Name',
          hint: 'e.g. Surf & Water Sports Club',
          controller: nameController,
          onChanged: onFieldChanged,
          helper: nameLength > 0 && nameLength < CreateRsoScreen.minName
              ? 'At least ${CreateRsoScreen.minName} characters'
              : null,
        ),
        _Field(
          label: 'Contact Email (optional)',
          hint: 'your@uniandes.edu.co',
          controller: contactController,
          keyboardType: TextInputType.emailAddress,
          onChanged: onFieldChanged,
          helper: contactValid ? null : 'Enter a valid email address',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: kPageGutter),
          child: SectionLabel(text: 'Category'),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in RsoCategory.assignable)
                SelectableChip.choice(
                  label: option.label,
                  icon: option.icon,
                  selected: option == category,
                  onSelected: (_) => onCategoryChanged(option),
                ),
            ],
          ),
        ),
        if (category case final category?)
          _InterestPicker(
            category: category,
            interests: interests,
            selected: tagIds,
            onToggled: onTagToggled,
          ),
        const SizedBox(height: 20),
        _Field(
          label: 'Description',
          hint:
              "Describe your RSO's mission, activities, and what students "
              'can expect...',
          controller: descriptionController,
          maxLines: 4,
          onChanged: onFieldChanged,
          helper: descriptionLength < CreateRsoScreen.minDescription
              ? '$descriptionLength/${CreateRsoScreen.minDescription} '
                    'characters minimum'
              : null,
        ),
        if (error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 0, kPageGutter, 12),
            child: Text(
              error,
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: PrimaryButton(
            label: 'Submit for Review',
            busy: submitting,
            onPressed: canSubmit ? onSubmit : null,
          ),
        ),
      ],
    );
  }
}

/// Optional interest tags, from the chosen category. They decide which
/// students the group is recommended to; without any, the backend picks some
/// from the name and description.
class _InterestPicker extends StatelessWidget {
  const _InterestPicker({
    required this.category,
    required this.interests,
    required this.selected,
    required this.onToggled,
  });

  final RsoCategory category;
  final Future<List<Interest>> interests;
  final Set<int> selected;
  final ValueChanged<int> onToggled;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: interests,
      builder: (context, snapshot) {
        final options = [
          for (final interest in snapshot.data ?? const <Interest>[])
            if (interest.categorySlug == category.slug) interest,
        ];
        // Unavailable or none for this category: the backend still picks
        // tags, so the form works without them.
        if (options.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 20, kPageGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel(text: 'Interests (optional)'),
              const SizedBox(height: 4),
              Text(
                'Helps us suggest your group to the right students.',
                style: AppTheme.body(
                  size: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final interest in options)
                    SelectableChip.choice(
                      label: interest.name,
                      selected: selected.contains(interest.id),
                      onSelected: (_) => onToggled(interest.id),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    this.helper,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  /// What's missing, under the field.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageGutter, 0, kPageGutter, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(text: label),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: AppTheme.body(size: 14),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(hintText: hint),
          ),
          if (helper case final helper?) ...[
            const SizedBox(height: 6),
            Text(
              helper,
              style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _Confirmation extends StatelessWidget {
  const _Confirmation({required this.name, required this.onBack});

  final String name;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, kNavBarClearance),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.washStrong,
                borderRadius: BorderRadius.circular(AppRadius.hero),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text('Proposal Submitted!', style: AppTheme.heading(size: 24)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Your RSO proposal for '),
                  TextSpan(
                    text: name,
                    style: AppTheme.body(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const TextSpan(
                    text:
                        ' has been submitted to Uniandes Student Affairs for '
                        "review. You'll find it in My RSOs, and we'll notify "
                        "you when it's reviewed.",
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 14,
                height: 1.55,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 32),
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  child: Text(
                    'Back to Discover',
                    style: AppTheme.heading(
                      size: 15,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
