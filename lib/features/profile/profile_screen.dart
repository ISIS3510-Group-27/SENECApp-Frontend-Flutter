import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/selectable_chip.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/student_profile.dart';
import '../../state/app_state.dart';

/// The student's own page: identity, interests and account settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _settings = [
    ('Notifications', 'Manage event alerts'),
    ('Privacy Settings', 'Control who sees your profile'),
    ('University Verification', 'Verified via uniandes.edu.co'),
    ('Help & Support', 'Report an issue or give feedback'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final student = state.student;

    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarClearance),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SENECAPP · STUDENT',
                      style: AppTheme.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.mutedForeground,
                        letterSpacing: 1.8,
                      ),
                    ),
                    Text('Profile', style: AppTheme.heading(size: 24)),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Image.asset(
                  BrandAssets.mascotHat,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: _IdentityCard(
            student: student,
            joinedCount: state.joinedCount,
            eventsAttended: state.eventsAttended,
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: kPageGutter),
          child: SectionLabel(text: 'Interests'),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final interest in student.interests)
                StaticChip(label: interest),
              const _AddInterestChip(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: kPageGutter),
          child: SectionLabel(text: 'Account'),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
          child: AppCard(
            padding: EdgeInsets.zero,
            clipContents: true,
            child: Column(
              children: [
                for (final (index, (label, subtitle)) in _settings.indexed) ...[
                  _SettingsRow(label: label, subtitle: subtitle),
                  if (index < _settings.length - 1) const Divider(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.student,
    required this.joinedCount,
    required this.eventsAttended,
  });

  final StudentProfile student;
  final int joinedCount;
  final int eventsAttended;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.hero),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.secondary, AppColors.card],
          ),
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(AppRadius.hero),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    student.initials,
                    style: AppTheme.heading(
                      size: 22,
                      weight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(student.name, style: AppTheme.heading(size: 18)),
                      Text(
                        student.email,
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          // Darker than the card's navy-to-slate gradient
                          // rather than lighter: a tinted pill washes out
                          // against the top-left end of that gradient.
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                student.program,
                                style: AppTheme.body(
                                  size: 10,
                                  weight: FontWeight.w800,
                                  color: AppColors.foreground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _MiniStat(value: '$joinedCount', label: 'RSOs'),
                _MiniStat(value: '$eventsAttended', label: 'Events'),
                _MiniStat(value: '${student.yearsActive}', label: 'Years'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.heading(size: 20, weight: FontWeight.w900),
          ),
          Text(
            label,
            style: AppTheme.body(size: 11, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _AddInterestChip extends StatelessWidget {
  const _AddInterestChip();

  @override
  Widget build(BuildContext context) {
    return Material(
      // Same surface as the StaticChips it sits beside; the gold glyph is what
      // marks it as the actionable one in the row.
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Editing interests is coming soon.')),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 13, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: AppTheme.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        label,
        style: AppTheme.body(size: 14, weight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.body(size: 12, color: AppColors.mutedForeground),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppColors.mutedForeground,
      ),
      onTap: () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label is coming soon.'))),
    );
  }
}
