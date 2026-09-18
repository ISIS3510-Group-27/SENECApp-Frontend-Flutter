import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/app_notification.dart';
import '../../state/app_state.dart';

/// The notification inbox, reached from the bell on Discover.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadCount;

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Notifications',
                        style: AppTheme.heading(size: 20),
                      ),
                      Text(
                        '$unread unread',
                        style: AppTheme.body(
                          size: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread > 0)
                  _MarkAllReadButton(
                    onPressed: () => context.read<AppState>().markAllRead(),
                  ),
                const SizedBox(width: 8),
                RoundIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  size: 34,
                  iconSize: 16,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                kPageGutter,
                16,
                kPageGutter,
                kNavBarClearance,
              ),
              itemCount: state.notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notification = state.notifications[index];
                return _NotificationCard(
                  notification: notification,
                  unread: state.isUnread(notification.id),
                  onTap: () =>
                      context.read<AppState>().markRead(notification.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkAllReadButton extends StatelessWidget {
  const _MarkAllReadButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Mark all read',
            style: AppTheme.body(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.unread,
    required this.onTap,
  });

  final AppNotification notification;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      // Read notifications recede: dimmer surface, dimmer body text, no dot.
      color: unread ? AppColors.card : AppColors.cardMuted,
      border: unread ? AppColors.borderStrong : AppColors.border,
      onTap: unread ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TintedIconTile(
            icon: Icons.notifications_rounded,
            color: notification.color,
            size: 36,
            iconSize: 15,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  notification.source,
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w800,
                    color: notification.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.message,
                  style: AppTheme.body(
                    size: 14,
                    height: 1.35,
                    color: unread
                        ? AppColors.foreground
                        : AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  notification.time,
                  style: AppTheme.body(
                    size: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (unread) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
