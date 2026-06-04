import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/help/tiknet_faq_page.dart';
import 'package:hiddify/features/tiknet/inbox/tiknet_notifications_page.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/service/tiknet_notification_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_telemetry_service.dart';
import 'package:hiddify/features/tiknet/user_info/tiknet_diagnostic_page.dart';
import 'package:hiddify/features/tiknet/user_info/tiknet_logout_dialog.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// TikNet: حساب من — پروفایل، وضعیت اشتراک، آمار و میانبرهای پشتیبانی.
class TikNetUserInfoPage extends ConsumerStatefulWidget {
  const TikNetUserInfoPage({super.key});

  @override
  ConsumerState<TikNetUserInfoPage> createState() => _TikNetUserInfoPageState();
}

class _TikNetUserInfoPageState extends ConsumerState<TikNetUserInfoPage> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(tikNetInboxProvider);
    });
  }

  Future<void> _runSync(BuildContext context) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final sync = ref.read(syncServiceProvider);
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
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
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
    final appVersion = ref.watch(appInfoProvider).valueOrNull?.version;
    final profile = sync.getProfile();
    final lastSync = sync.getLastSyncTime();
    final expired = profile?.isExpired ?? sync.isSubscriptionExpired();
    final hasSubscription = profile?.hasSubscription ?? false;

    final displayName = profile?.fullName?.trim().isNotEmpty == true ? profile!.fullName! : profile?.username ?? '—';
    final username = profile?.username ?? '—';
    final trimmedName = displayName.trim();
    final initial = trimmedName.isNotEmpty ? trimmedName.substring(0, 1) : '؟';

    return Scaffold(
      backgroundColor: TikNetColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            centerTitle: true,
            title: const Text('حساب من'),
            actions: [
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: TikNetColors.error, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        toPersianDigits('$unread'),
                        style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      TikNetColors.primary.withValues(alpha: 0.35),
                      TikNetColors.background,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: TikNetColors.primary.withValues(alpha: 0.25),
                          child: Text(
                            initial,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: TikNetColors.primary,
                            ),
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(displayName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              const Gap(4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: TikNetColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: TikNetColors.border),
                                ),
                                child: Text(
                                  username,
                                  style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusBadge(expired: expired, hasSubscription: hasSubscription),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _StatsGrid(
                  planName: profile?.planName,
                  expireLabel: profile?.expireDate != null ? formatShamsiDate(profile!.expireDate) : '—',
                  daysRemaining: profile?.daysRemaining != null
                      ? toPersianDigits('${profile!.daysRemaining}')
                      : _daysRemaining(profile?.expireDate),
                  traffic: _hasTraffic(profile) ? _formatTraffic(profile!.trafficUsedBytes, profile.trafficLimitBytes) : null,
                  lastSync: lastSync != null ? '${formatShamsiDate(lastSync)} ${_formatTime(lastSync)}' : '—',
                  appVersion: appVersion != null ? 'نسخه $appVersion' : '—',
                ),
                const Gap(20),
                FilledButton.icon(
                  onPressed: _syncing ? null : () => _runSync(context),
                  icon: _syncing
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded),
                  label: Text(_syncing ? 'در حال بروزرسانی…' : 'بروزرسانی اشتراک'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const Gap(24),
                _SectionTitle(title: 'خدمات'),
                const Gap(8),
                _ActionCard(
                  children: [
                    _ActionTile(
                      icon: Icons.notifications_outlined,
                      label: 'اعلان‌ها',
                      badge: unread > 0 ? toPersianDigits('$unread') : null,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TikNetNotificationsPage())),
                    ),
                    const Divider(height: 1, indent: 56),
                    _ActionTile(
                      icon: Icons.help_outline_rounded,
                      label: 'راهنما و سوالات',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TikNetFaqPage())),
                    ),
                    const Divider(height: 1, indent: 56),
                    _ActionTile(
                      icon: Icons.article_outlined,
                      label: 'گزارش تشخیصی (لاگ)',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TikNetDiagnosticPage())),
                    ),
                    const Divider(height: 1, indent: 56),
                    _ActionTile(
                      icon: Icons.bug_report_outlined,
                      label: 'ارسال گزارش خطا به پنل',
                      onTap: () async {
                        await ref.read(tikNetTelemetryServiceProvider).reportUserIssue(
                          message: 'manual_report_from_account',
                          context: 'user_info_page',
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('گزارش خطا به پنل ارسال شد.')),
                        );
                      },
                    ),
                  ],
                ),
                if (profile?.brand?.supportTelegram?.isNotEmpty == true) ...[
                  const Gap(20),
                  _SectionTitle(title: 'پشتیبانی'),
                  const Gap(8),
                  _ActionCard(
                    children: [
                      _ActionTile(
                        icon: Icons.support_agent_rounded,
                        label: 'پشتیبانی تلگرام',
                        onTap: () {
                          final tg = profile!.brand!.supportTelegram!.replaceFirst('@', '');
                          UriUtils.tryLaunch(Uri.parse('https://t.me/$tg'));
                        },
                      ),
                    ],
                  ),
                ],
                const Gap(12),
                _RenewButton(profile: profile),
                const Gap(20),
                OutlinedButton.icon(
                  onPressed: () => showTikNetLogoutDialog(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('خروج از حساب'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TikNetColors.error,
                    side: const BorderSide(color: TikNetColors.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _daysRemaining(DateTime? expireDate) {
    if (expireDate == null) return '—';
    final now = DateTime.now();
    if (now.isAfter(expireDate)) return '۰';
    return toPersianDigits(expireDate.difference(now).inDays.toString());
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
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.expired, required this.hasSubscription});

  final bool expired;
  final bool hasSubscription;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;
    if (expired) {
      color = TikNetColors.error;
      label = 'منقضی';
      icon = Icons.error_outline_rounded;
    } else if (!hasSubscription) {
      color = const Color(0xFFEAB308);
      label = 'بدون سرویس';
      icon = Icons.info_outline_rounded;
    } else {
      color = TikNetColors.connected;
      label = 'فعال';
      icon = Icons.check_circle_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const Gap(4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: TikNetColors.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.expireLabel,
    required this.daysRemaining,
    required this.lastSync,
    required this.appVersion,
    this.planName,
    this.traffic,
  });

  final String? planName;
  final String expireLabel;
  final String daysRemaining;
  final String? traffic;
  final String lastSync;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (planName?.isNotEmpty == true) ...[
          _StatTile(icon: Icons.workspace_premium_outlined, label: 'پلن', value: planName!, wide: true),
          const Gap(10),
        ],
        Row(
          children: [
            Expanded(child: _StatTile(icon: Icons.event_outlined, label: 'انقضا', value: expireLabel)),
            const Gap(10),
            Expanded(child: _StatTile(icon: Icons.timelapse_rounded, label: 'روز باقی‌مانده', value: daysRemaining)),
          ],
        ),
        if (traffic != null) ...[
          const Gap(10),
          _StatTile(icon: Icons.data_usage_rounded, label: 'مصرف حجم', value: traffic!, wide: true),
        ],
        const Gap(10),
        Row(
          children: [
            Expanded(child: _StatTile(icon: Icons.update_rounded, label: 'آخرین بروزرسانی', value: lastSync)),
            const Gap(10),
            Expanded(
              child: _StatTile(
                icon: Icons.smartphone_rounded,
                label: 'نسخه',
                value: appVersion,
                valueStyle: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool wide;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TikNetColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TikNetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: TikNetColors.primary),
              const Gap(6),
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: TikNetColors.onSurfaceVariant)),
            ],
          ),
          const Gap(6),
          Text(
            value,
            style: valueStyle ?? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TikNetColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TikNetColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: TikNetColors.primary),
      title: Text(label, style: theme.textTheme.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: TikNetColors.error, borderRadius: BorderRadius.circular(10)),
              child: Text(badge!, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
            ),
          Icon(Icons.chevron_left_rounded, color: TikNetColors.onSurfaceVariant),
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
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
