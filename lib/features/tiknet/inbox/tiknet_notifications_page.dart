import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/model/tiknet_notification.dart';
import 'package:hiddify/features/tiknet/service/tiknet_notification_service.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetNotificationsPage extends ConsumerWidget {
  const TikNetNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final inboxAsync = ref.watch(tikNetInboxProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('اعلان‌ها'), centerTitle: true),
      body: inboxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text('بارگذاری اعلان‌ها ناموفق بود.', style: TextStyle(color: theme.colorScheme.error)),
        ),
        data: (inbox) {
          if (inbox.notifications.isEmpty) {
            return Center(
              child: Text(
                'اعلان جدیدی ندارید.',
                style: theme.textTheme.bodyLarge?.copyWith(color: TikNetColors.onSurfaceVariant),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tikNetInboxProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: inbox.notifications.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (context, index) => _NotificationTile(notification: inbox.notifications[index]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerStatefulWidget {
  const _NotificationTile({required this.notification});
  final TikNetNotification notification;

  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  bool _expanded = false;

  Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'warning':
        return const Color(0xFFEAB308);
      case 'promo':
        return TikNetColors.connected;
      default:
        return TikNetColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.notification;
    final unread = !n.read;

    return Card(
      color: unread ? TikNetColors.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: () async {
          setState(() => _expanded = !_expanded);
          if (unread) await markTikNetNotificationRead(ref, n.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 10, color: unread ? _typeColor(n.type) : Colors.transparent),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      n.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (n.createdAt != null)
                    Text(
                      formatShamsiDate(n.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                    ),
                ],
              ),
              if (_expanded) ...[
                const Gap(12),
                Text(n.body, style: theme.textTheme.bodyMedium),
              ] else ...[
                const Gap(6),
                Text(
                  n.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
