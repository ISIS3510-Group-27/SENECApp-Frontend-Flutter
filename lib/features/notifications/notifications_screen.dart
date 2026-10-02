import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/analytics/analytics.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/entry_point.dart';
import '../../state/app_state.dart';
import '../rso_detail/rso_detail_screen.dart';
import '../shell/track_screen.dart';

/// The notification inbox, reached from the bell on Discover.
///
/// Tapping a notification records it as opened and "Mark all read" records
/// the rest as dismissed: BQ8 compares the two per notification type.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen());

  void _open(BuildContext context, AppNotification notification) {
    context.read<AppState>().openNotification(notification);
    if (notification.groupId case final groupId?) {
      Navigator.of(context).push(
        RsoDetailScreen.route(groupId, entryPoint: EntryPoint.notification),
      );
    }
  }

  @override
  Widget build(BuildContext context) => TrackScreen(
    name: Screens.notifications,
    ready: context.select<AppState, bool>(
      (s) => s.notifications != null || s.notificationsError != null,
    ),
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final state = context.watch<AppState>();
    final unread = state.unreadCount;
    final notifications = state.notifications;

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              kPageGutter,
              12,
              kPageGutter,
              16,
            ),
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
                      Text('Notifications', style: AppTheme.heading(size: 20)),
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
            child: RefreshIndicator(
              onRefresh: state.refreshNotifications,
              color: AppColors.accent,
              child: switch (notifications) {
                null when state.notificationsError != null => ListView(
                  children: [
                    ErrorBlock(
                      message: state.notificationsError!,
                      onRetry: state.refreshNotifications,
                    ),
                  ],
                ),
                null => ListView(children: const [LoadingBlock()]),
                [] => ListView(children: const [_EmptyInbox()]),
                _ => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    kPageGutter,
                    16,
                    kPageGutter,
                    kNavBarClearance,
                  ),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return _NotificationCard(
                      notification: notification,
                      unread: notification.unread,
                      onTap: () => _open(context, notification),
                    );
                  },
                ),
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
      // Read ones still lead to their group; a read one with nowhere to go
      // has nothing left to do.
      onTap: unread || notification.groupId != null ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TintedIconTile(
            icon: notification.icon,
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
                  notification.title,
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w800,
                    color: notification.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.body,
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kPageGutter,
        vertical: 40,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 40,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 12),
          Text("You're all caught up", style: AppTheme.heading(size: 16)),
          const SizedBox(height: 4),
          Text(
            'News from your organizations will show up here.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
