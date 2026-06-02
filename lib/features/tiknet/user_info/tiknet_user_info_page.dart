import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/help/tiknet_faq_page.dart';
import 'package:hiddify/features/tiknet/inbox/tiknet_notifications_page.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/user_info/tiknet_logout_dialog.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/service/tiknet_notification_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_telemetry_service.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// TikNet: حساب من — نام کاربر، وضعیت اشتراک، تاریخ انقضا، روزهای باقی‌مانده، آخرین بروزرسانی، دکمه سینک و خروج.
class TikNetUserInfoPage extends ConsumerStatefulWidget {
  const TikNetUserInfoPage({super.key});

  @override
  ConsumerState<TikNetUserInfoPage> createState() => _TikNetUserInfoPageState();
}

class _TikNetUserInfoPageState extends ConsumerState<TikNetUserInfoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(tikNetInboxProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authServiceProvider);
    ref.watch(Preferences.tikNetCachedProfile);
    ref.watch(Preferences.tikNetLastSyncTime);
    final unread = ref.watch(tikNetUnreadCountProvider);

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
    final expired = profile?.isExpired ?? sync.isSubscriptionExpired();

    // وضعیت اشتراک: فعال (سبز)، منقضی (قرمز)، بدون سرویس (زرد)
    final bool hasSubscription = profile?.hasSubscription ?? false;
    final statusCard = _buildStatusCard(theme, hasSubscription: hasSubscription, expired: expired);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حساب من'),
        centerTitle: true,
        actions: [
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: TikNetColors.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    toPersianDigits('$unread'),
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
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
                  if (profile?.planName?.isNotEmpty == true) ...[
                    _row(theme, 'پلن', profile!.planName!),
                    const Divider(height: 24, color: TikNetColors.border),
                  ],
                  _row(theme, 'تاریخ انقضا', profile?.expireDate != null ? formatShamsiDate(profile!.expireDate) : '—'),
                  const Divider(height: 24, color: TikNetColors.border),
                  _row(
                    theme,
                    'روزهای باقی‌مانده',
                    profile?.daysRemaining != null
                        ? toPersianDigits('${profile!.daysRemaining}')
                        : _daysRemaining(profile?.expireDate),
                  ),
                  if (_hasTraffic(profile)) ...[
                    const Divider(height: 24, color: TikNetColors.border),
                    _row(theme, 'مصرف حجم', _formatTraffic(profile!.trafficUsedBytes, profile.trafficLimitBytes)),
                  ],
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
                final ok = await sync.syncAllAndApplyProfile();
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
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TikNetNotificationsPage()),
              );
            },
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(toPersianDigits('$unread')),
              child: const Icon(Icons.notifications_outlined),
            ),
            label: const Text('اعلان‌ها'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TikNetFaqPage()));
            },
            icon: const Icon(Icons.help_outline_rounded),
            label: const Text('راهنما و سوالات'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(tikNetTelemetryServiceProvider).reportUserIssue(
                message: 'manual_report_from_account',
                context: 'user_info_page',
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('گزارش خطا به پنل ارسال شد. از بخش Telemetry ادمین قابل مشاهده است.')),
              );
            },
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('ارسال گزارش خطا به پنل'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (profile?.brand?.supportTelegram?.isNotEmpty == true) ...[
            const Gap(12),
            OutlinedButton.icon(
              onPressed: () {
                final tg = profile!.brand!.supportTelegram!.replaceFirst('@', '');
                UriUtils.tryLaunch(Uri.parse('https://t.me/$tg'));
              },
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('پشتیبانی تلگرام'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
          const Gap(12),
          _RenewButton(profile: profile),
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () => showTikNetLogoutDialog(context, ref),
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

  bool _hasTraffic(TikNetUserInfo? profile) {
    if (profile == null) return false;
    return (profile.trafficUsedBytes ?? 0) > 0 || (profile.trafficLimitBytes ?? 0) > 0;
  }

  String _formatTraffic(int? used, int? limit) {
    String fmt(int bytes) {
      if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
      if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(0)} MB';
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    final u = used ?? 0;
    if (limit == null || limit <= 0) return fmt(u);
    return '${fmt(u)} / ${fmt(limit)}';
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

class _RenewButton extends ConsumerWidget {
  const _RenewButton({this.profile});
  final TikNetUserInfo? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profile?.shopEnabled == false) return const SizedBox.shrink();

    return FutureBuilder<List<TikNetCustomerOrder>>(
      future: _loadOrders(ref),
      builder: (context, snapshot) {
        TikNetCustomerOrder? withUrl;
        for (final o in snapshot.data ?? const <TikNetCustomerOrder>[]) {
          if (o.renewUrl != null && o.renewUrl!.isNotEmpty) {
            withUrl = o;
            break;
          }
        }
        final url = withUrl?.renewUrl;
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        return FilledButton.tonalIcon(
          onPressed: () => UriUtils.tryLaunch(Uri.parse(url)),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('تمدید / خرید'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        );
      },
    );
  }

  Future<List<TikNetCustomerOrder>> _loadOrders(WidgetRef ref) async {
    final baseUrl = ref.read(Preferences.tikNetPanelBaseUrl);
    final token = ref.read(authServiceProvider).getToken();
    if (baseUrl.isEmpty || token.isEmpty) return const [];
    try {
      return await ref.read(tikNetApiProvider).getOrders(baseUrl: baseUrl, accessToken: token);
    } catch (_) {
      return const [];
    }
  }
}
