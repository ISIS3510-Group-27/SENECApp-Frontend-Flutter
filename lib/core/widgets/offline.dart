import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/offline_cache.dart';
import '../../state/connection_status.dart';
import '../format/dates.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Whether the phone has a connection, as far as the app knows. `true` where
/// no [ConnectionStatus] is provided (widget tests of a single screen).
bool isOnline(BuildContext context, {bool listen = true}) =>
    (listen
            ? context.watch<ConnectionStatus?>()
            : context.read<ConnectionStatus?>())
        ?.online ??
    true;

/// The strip across the top of the app while there's no connection, or while
/// the backend can't be reached and the screens show the phone's copy.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final online = isOnline(context);
    final showingCopy = context.watch<DataFreshness?>()?.anyCached ?? false;

    final (icon, text) = !online
        ? (
            Icons.wifi_off_rounded,
            "You're offline. You can still browse what you saw last.",
          )
        : showingCopy
        ? (
            Icons.cloud_off_rounded,
            "Can't reach SENECApp. Showing what you saw last.",
          )
        : (null, null);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: AppColors.secondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: AppTheme.body(size: 12, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A line above a list or page shown from the phone's copy: how old it is, and
/// what that means on this screen. Hidden while the data is live.
class SavedCopyNote extends StatelessWidget {
  const SavedCopyNote({
    super.key,
    required this.dataKeys,
    required this.message,
    this.padding = EdgeInsets.zero,
  });

  /// The [DataFreshness] keys of what the screen shows.
  final List<String> dataKeys;

  /// What still works, or what doesn't, on this screen.
  final String message;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final freshness = context.watch<DataFreshness?>();
    final saved = [for (final key in dataKeys) ?freshness?.cachedAt(key)];
    if (saved.isEmpty) return const SizedBox.shrink();
    // The oldest part decides how out of date the screen may be.
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
  }
}

/// An inline line explaining what on this screen waits for the connection.
class OfflineNote extends StatelessWidget {
  const OfflineNote(this.message, {super.key, this.padding = EdgeInsets.zero});

  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: AppTheme.body(size: 12, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stops an action that needs the backend when there's no connection, and
/// says why instead of letting the request fail. Returns whether to go on.
Future<bool> ensureOnline(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  if (isOnline(context, listen: false)) return true;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      icon: const Icon(Icons.wifi_off_rounded, color: AppColors.accent),
      title: Text(title, style: AppTheme.heading(size: 18)),
      content: Text(message, style: AppTheme.body(size: 14, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return false;
}
