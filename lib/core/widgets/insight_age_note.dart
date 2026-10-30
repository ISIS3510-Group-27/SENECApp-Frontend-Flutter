import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_services.dart';
import '../format/dates.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class InsightAgeNote extends StatelessWidget {
  const InsightAgeNote({
    super.key,
    required this.dataKeys,
    required this.message,
    this.padding = EdgeInsets.zero,
  });

  final List<String> dataKeys;
  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final insights = context.read<AppServices>().insights;
    return ListenableBuilder(
      listenable: insights,
      builder: (context, _) {
        final saved = [
          for (final key in dataKeys) ?insights.copySavedAt(key),
        ];
        if (saved.isEmpty) return const SizedBox.shrink();
        final oldest = saved.reduce((a, b) => a.isBefore(b) ? a : b);
        return Padding(
          padding: padding,
          child: Container(
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
                    'Saved ${Dates.ago(oldest)}. $message',
                    style: AppTheme.body(
                      size: 12,
                      height: 1.4,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
