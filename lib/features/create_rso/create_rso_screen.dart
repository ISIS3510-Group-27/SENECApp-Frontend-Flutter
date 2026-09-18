import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/rso_category.dart';

/// The proposal form for a new organization.
///
/// Submission is local to this prototype: it swaps the form for a confirmation
/// rather than calling anything. Name and category are the two fields Student
/// Affairs needs to triage a proposal, so the button stays disabled until both
/// are filled.
class CreateRsoScreen extends StatefulWidget {
  const CreateRsoScreen({super.key});

  @override
  State<CreateRsoScreen> createState() => _CreateRsoScreenState();
}

class _CreateRsoScreenState extends State<CreateRsoScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _descriptionController = TextEditingController();

  RsoCategory? _category;
  bool _submitted = false;

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty && _category != null;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _submitted
          ? _Confirmation(
              name: _nameController.text.trim(),
              onBack: () => Navigator.of(context).pop(),
            )
          : _Form(
              nameController: _nameController,
              contactController: _contactController,
              descriptionController: _descriptionController,
              category: _category,
              canSubmit: _canSubmit,
              onCategoryChanged: (category) =>
                  setState(() => _category = category),
              // Any keystroke can flip the submit button's state, so the whole
              // form rebuilds on change rather than tracking each field.
              onFieldChanged: () => setState(() {}),
              onSubmit: () => setState(() => _submitted = true),
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
    required this.canSubmit,
    required this.onCategoryChanged,
    required this.onFieldChanged,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController contactController;
  final TextEditingController descriptionController;
  final RsoCategory? category;
  final bool canSubmit;
  final ValueChanged<RsoCategory> onCategoryChanged;
  final VoidCallback onFieldChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
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
        ),
        _Field(
          label: 'Contact Email',
          hint: 'your@uniandes.edu.co',
          controller: contactController,
          keyboardType: TextInputType.emailAddress,
          onChanged: onFieldChanged,
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
        const SizedBox(height: 20),
        _Field(
          label: 'Description',
          hint:
              "Describe your RSO's mission, activities, and what students "
              'can expect...',
          controller: descriptionController,
          maxLines: 4,
          onChanged: onFieldChanged,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: _SubmitButton(enabled: canSubmit, onPressed: onSubmit),
        ),
      ],
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
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

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
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.primary : AppColors.secondary,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: double.infinity,
          height: 54,
          alignment: Alignment.center,
          child: Text(
            'Submit for Review',
            style: AppTheme.heading(
              size: 16,
              weight: FontWeight.w700,
              color: enabled ? Colors.white : AppColors.mutedForeground,
            ),
          ),
        ),
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
                        ' has been submitted to Uniandes Student Affairs '
                        'for review. You will receive a response within 5 '
                        'business days.',
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
