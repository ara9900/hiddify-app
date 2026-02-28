import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// TikNet: حساب من — نام کاربر، وضعیت اشتراک، تاریخ انقضا، روزهای باقی‌مانده، آخرین بروزرسانی، دکمه سینک و خروج.
class TikNetUserInfoPage extends ConsumerWidget {
  const TikNetUserInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authServiceProvider);
    ref.watch(Preferences.tikNetCachedProfile);
    ref.watch(Preferences.tikNetLastSyncTime);

    if (!auth.isLoggedIn()) {
      return Scaffold(
        appBar: AppBar(title: const Text('حساب من'), centerTitle: true),
        body: Center(
          child: Text(
            'وارد نشده‌اید.',
            style: theme.textTheme.bodyLarge?.copyWith(color: TikNetColors.onSurfaceVariant),
          ),
        ),
      );
    }

    final sync = ref.read(syncServiceProvider);
    final profile = sync.getProfile();
    final lastSync = sync.getLastSyncTime();
    final expired = sync.isSubscriptionExpired();

    // وضعیت اشتراک: فعال (سبز)، منقضی (قرمز)، بدون سرویس (زرد)
    final bool hasSubscription = profile?.hasSubscription ?? false;
    final statusCard = _buildStatusCard(theme, hasSubscription: hasSubscription, expired: expired);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حساب من'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.fullName?.trim().isNotEmpty == true ? profile!.fullName! : profile?.username ?? '—',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (profile?.fullName?.trim().isNotEmpty == true) ...[
                    const Gap(4),
                    Text(
                      profile!.username,
                      style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Gap(16),
          statusCard,
          const Gap(20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(theme, 'تاریخ انقضا', profile?.expireDate != null ? formatShamsiDate(profile!.expireDate) : '—'),
                  const Divider(height: 24, color: TikNetColors.border),
                  _row(theme, 'روزهای باقی‌مانده', _daysRemaining(profile?.expireDate)),
                  const Divider(height: 24, color: TikNetColors.border),
                  _row(
                    theme,
                    'آخرین بروزرسانی',
                    lastSync != null ? '${formatShamsiDate(lastSync)} ${_formatTime(lastSync)}' : '—',
                  ),
                ],
              ),
            ),
          ),
          const Gap(24),
          FilledButton.icon(
            onPressed: () async {
              try {
                final ok = await sync.syncAll();
                if (context.mounted && ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('بروزرسانی انجام شد.'),
                      backgroundColor: TikNetColors.connected,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } on SyncTokenExpiredException {
                if (context.mounted) context.go('/login');
              }
            },
            icon: const Icon(Icons.sync_rounded),
            label: const Text('بروزرسانی'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('خروج'),
            style: OutlinedButton.styleFrom(
              foregroundColor: TikNetColors.error,
              side: const BorderSide(color: TikNetColors.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, {required bool hasSubscription, required bool expired}) {
    Color bgColor;
    String text;
    if (expired) {
      bgColor = TikNetColors.error.withValues(alpha: 0.2);
      text = 'اشتراک شما به پایان رسیده';
    } else if (!hasSubscription) {
      bgColor = const Color(0xFFEAB308).withValues(alpha: 0.2); // زرد
      text = 'سرویس فعالی ندارید';
    } else {
      bgColor = TikNetColors.connected.withValues(alpha: 0.2);
      text = 'فعال';
    }

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              expired ? Icons.error_outline_rounded : (hasSubscription ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded),
              color: expired ? TikNetColors.error : (hasSubscription ? TikNetColors.connected : const Color(0xFFEAB308)),
              size: 28,
            ),
            const Gap(16),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _daysRemaining(DateTime? expireDate) {
    if (expireDate == null) return '—';
    final now = DateTime.now();
    if (now.isAfter(expireDate)) return '۰';
    final days = expireDate.difference(now).inDays;
    return toPersianDigits(days.toString());
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return toPersianDigits('$h:$m');
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
