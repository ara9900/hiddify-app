import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/help/tiknet_faq_page.dart';
import 'package:hiddify/features/tiknet/inbox/tiknet_notifications_page.dart';
import 'package:hiddify/features/tiknet/model/tiknet_referral.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/service/tiknet_notification_service.dart';
import 'package:hiddify/features/tiknet/user_info/tiknet_logout_dialog.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

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

    final fromProfile = (profile?.username ?? '').trim();
    final fromSaved = ref.watch(Preferences.tikNetSavedUsername).trim();
    final username = fromProfile.isNotEmpty
        ? fromProfile
        : (fromSaved.isNotEmpty ? fromSaved : '—');
    final fullName = profile?.fullName?.trim();
    final initial = username != '—' ? username.substring(0, 1) : '؟';

    return Scaffold(
      backgroundColor: TikNetColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            centerTitle: true,
            expandedHeight: 168,
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
              collapseMode: CollapseMode.pin,
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
                              Text(
                                'نام کاربری',
                                style: theme.textTheme.labelMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                              ),
                              const Gap(2),
                              Text(
                                username,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (fullName != null && fullName.isNotEmpty && fullName != username) ...[
                                const Gap(4),
                                Text(
                                  fullName,
                                  style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                                ),
                              ],
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
                  planName: profile?.planName?.trim().isNotEmpty == true ? profile!.planName!.trim() : '—',
                  expireLabel: profile?.expireDate != null ? formatShamsiDate(profile!.expireDate) : '—',
                  daysRemaining: profile?.daysRemaining != null
                      ? toPersianDigits('${profile!.daysRemaining}')
                      : _daysRemaining(profile?.expireDate),
                  trafficLabel: _hasTraffic(profile)
                      ? _formatTraffic(profile!.trafficUsedBytes, profile.trafficLimitBytes)
                      : null,
                  trafficUsedBytes: profile?.trafficUsedBytes,
                  trafficLimitBytes: profile?.trafficLimitBytes,
                  lastSync: lastSync != null ? '${formatShamsiDate(lastSync)} ${_formatTime(lastSync)}' : '—',
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
                const _SectionTitle(title: 'معرف'),
                const Gap(8),
                const _ReferralSection(),
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
                const Gap(16),
                Text(
                  appVersion != null ? 'نسخه $appVersion' : '—',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
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

class _ReferralSection extends ConsumerStatefulWidget {
  const _ReferralSection();

  @override
  ConsumerState<_ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends ConsumerState<_ReferralSection> {
  TikNetReferralInfo? _info;
  Object? _error;
  bool _loading = true;
  bool _attaching = false;
  bool _unavailable = false;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _unavailable = false;
    });
    final baseUrl = ref.read(Preferences.tikNetPanelBaseUrl);
    final token = ref.read(authServiceProvider).getToken();
    if (baseUrl.isEmpty || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'نشست نامعتبر است.';
        });
      }
      return;
    }
    try {
      final info = await ref.read(tikNetApiProvider).getReferral(
            baseUrl: baseUrl,
            accessToken: token,
          );
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } on TikNetApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.statusCode == 404 || e.statusCode == 501) {
          _unavailable = true;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('کد معرف کپی شد.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _share(TikNetReferralInfo info) async {
    final code = info.referralCode;
    final url = (info.shareUrl ?? '').trim();
    final custom = (info.shareText ?? '').trim();
    final text = custom.isNotEmpty
        ? custom
        : [
            'با کد معرف من در تیک‌نت ثبت‌نام/خرید کن و پاداش بگیر:',
            if (code.isNotEmpty) 'کد: $code',
            if (url.isNotEmpty) url,
          ].join('\n');
    await Share.share(text, subject: 'دعوت به تیک‌نت');
  }

  Future<void> _attach() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _attaching) return;
    setState(() => _attaching = true);
    final baseUrl = ref.read(Preferences.tikNetPanelBaseUrl);
    final token = ref.read(authServiceProvider).getToken();
    try {
      await ref.read(tikNetApiProvider).attachReferral(
            baseUrl: baseUrl,
            accessToken: token,
            referralCode: code,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('کد معرف ثبت شد.'),
          backgroundColor: TikNetColors.connected,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _codeController.clear();
      await _load();
    } on TikNetApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: TikNetColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ثبت کد معرف ناموفق بود.'),
          backgroundColor: TikNetColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TikNetColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TikNetColors.border),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_unavailable) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TikNetColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TikNetColors.border),
        ),
        child: Text(
          'سیستم معرف به‌زودی فعال می‌شود.',
          style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
        ),
      );
    }

    if (_error != null || _info == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TikNetColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TikNetColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _error?.toString() ?? 'خطا در دریافت اطلاعات معرف',
              style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
            ),
            const Gap(10),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      );
    }

    final info = _info!;
    final code = info.referralCode;
    final attached = (info.attachedReferrerCode ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TikNetColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TikNetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'دوستان را دعوت کنید؛ با تکمیل هر مرحله جایزه بگیرید.',
            style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
          ),
          if (info.referrerReward.amount > 0 || info.inviteeReward.amount > 0) ...[
            const Gap(8),
            Text(
              'پاداش شما: ${info.referrerReward.labelFa} · پاداش دوست: ${info.inviteeReward.labelFa}',
              style: theme.textTheme.labelMedium?.copyWith(color: TikNetColors.primary),
            ),
          ],
          const Gap(14),
          Text('کد معرف شما', style: theme.textTheme.labelMedium?.copyWith(color: TikNetColors.onSurfaceVariant)),
          const Gap(6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: TikNetColors.surfaceVariant.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: TikNetColors.border),
                  ),
                  child: Text(
                    code.isEmpty ? '—' : code,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const Gap(8),
              IconButton.filledTonal(
                onPressed: code.isEmpty ? null : () => _copyCode(code),
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'کپی',
              ),
              IconButton.filledTonal(
                onPressed: code.isEmpty ? null : () => _share(info),
                icon: const Icon(Icons.share_rounded),
                tooltip: 'اشتراک‌گذاری',
              ),
            ],
          ),
          const Gap(14),
          Row(
            children: [
              Expanded(
                child: _ReferralStatChip(
                  label: 'دعوت‌ها',
                  value: toPersianDigits('${info.stats.invitedCount}'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: _ReferralStatChip(
                  label: 'پاداش‌خورده',
                  value: toPersianDigits('${info.stats.rewardedCount}'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: _ReferralStatChip(
                  label: 'در انتظار',
                  value: toPersianDigits('${info.stats.pendingCount}'),
                ),
              ),
            ],
          ),
          const Gap(16),
          _ReferralProgressBox(info: info),
          if (attached.isNotEmpty) ...[
            const Gap(14),
            Text(
              'معرف شما: $attached',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ] else if (info.canAttachReferrer) ...[
            const Gap(16),
            Text(
              'کد معرف دارید؟',
              style: theme.textTheme.labelMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
            ),
            const Gap(6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _attach(),
                    decoration: const InputDecoration(
                      hintText: 'کد معرف',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Gap(8),
                FilledButton(
                  onPressed: _attaching ? null : _attach,
                  child: _attaching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('ثبت'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferralStatChip extends StatelessWidget {
  const _ReferralStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: TikNetColors.surfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Gap(2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: TikNetColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ReferralProgressBox extends StatelessWidget {
  const _ReferralProgressBox({required this.info});

  final TikNetReferralInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = info.progress;
    final rewarded = progress?.rewardedCount ?? info.stats.rewardedCount;

    final candidates = <int>[
      progress?.currentTarget ?? 0,
      progress?.nextMilestone?.invitesRequired ?? 0,
      if (info.milestones.isNotEmpty) info.milestones.first.invitesRequired,
    ];
    final target = candidates.firstWhere((t) => t > 0, orElse: () => 5);

    final completedAll = progress?.completedAll == true ||
        (info.milestones.isNotEmpty && rewarded >= info.milestones.last.invitesRequired && info.milestones.last.invitesRequired > 0);

    if (completedAll) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TikNetColors.connected.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TikNetColors.connected.withValues(alpha: 0.35)),
        ),
        child: Text(
          'همه مراحل دعوت تکمیل شد. تعداد دعوت‌های موفق: ${toPersianDigits('$rewarded')}',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }

    final displayRewarded = rewarded > target ? target : rewarded;
    final ratio = progress != null
        ? progress.progressRatio
        : (target > 0 ? (displayRewarded / target).clamp(0.0, 1.0) : 0.0);
    final labelRaw = (progress?.currentLabel ?? '').trim().isNotEmpty
        ? progress!.currentLabel!.trim()
        : '$displayRewarded از $target';
    final label = toPersianDigits(labelRaw);

    var caption = (progress?.rewardCaption ?? '').trim();
    if (caption.isEmpty) {
      caption = progress?.nextMilestone?.rewardCaptionFa ?? '';
    }
    if (caption.isEmpty && info.milestones.isNotEmpty) {
      caption = info.milestones.first.rewardCaptionFa;
    }
    if (caption.isEmpty) {
      caption = 'جایزه پس از تکمیل این مرحله از پنل اعمال می‌شود';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TikNetColors.surfaceVariant.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TikNetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تعداد کاربر دعوت‌شده با کد شما: $label',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Gap(10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: TikNetColors.border,
              color: TikNetColors.primary,
            ),
          ),
          const Gap(10),
          Text(
            caption,
            style: theme.textTheme.labelLarge?.copyWith(color: TikNetColors.primary),
          ),
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
    required this.planName,
    required this.expireLabel,
    required this.daysRemaining,
    required this.lastSync,
    this.trafficLabel,
    this.trafficUsedBytes,
    this.trafficLimitBytes,
  });

  final String planName;
  final String expireLabel;
  final String daysRemaining;
  final String lastSync;
  final String? trafficLabel;
  final int? trafficUsedBytes;
  final int? trafficLimitBytes;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(icon: Icons.workspace_premium_outlined, label: 'پلن', value: planName)),
            const Gap(10),
            Expanded(child: _StatTile(icon: Icons.event_outlined, label: 'انقضا', value: expireLabel)),
          ],
        ),
        const Gap(10),
        Row(
          children: [
            Expanded(child: _StatTile(icon: Icons.timelapse_rounded, label: 'روز باقی‌مانده', value: daysRemaining)),
            const Gap(10),
            Expanded(child: _StatTile(icon: Icons.update_rounded, label: 'آخرین بروزرسانی', value: lastSync)),
          ],
        ),
        if (trafficLabel != null) ...[
          const Gap(10),
          _TrafficStatTile(
            label: trafficLabel!,
            usedBytes: trafficUsedBytes ?? 0,
            limitBytes: trafficLimitBytes ?? 0,
          ),
        ],
      ],
    );
  }
}

class _TrafficStatTile extends StatelessWidget {
  const _TrafficStatTile({
    required this.label,
    required this.usedBytes,
    required this.limitBytes,
  });

  final String label;
  final int usedBytes;
  final int limitBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLimit = limitBytes > 0;
    final ratio = hasLimit ? (usedBytes / limitBytes).clamp(0.0, 1.0) : null;

    return Container(
      width: double.infinity,
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
              const Icon(Icons.data_usage_rounded, size: 18, color: TikNetColors.primary),
              const Gap(6),
              Text(
                'مصرف حجم',
                style: theme.textTheme.labelSmall?.copyWith(color: TikNetColors.onSurfaceVariant),
              ),
            ],
          ),
          const Gap(6),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasLimit) ...[
            const Gap(10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: TikNetColors.border,
                color: (ratio != null && ratio >= 0.9) ? TikNetColors.error : TikNetColors.primary,
              ),
            ),
          ],
        ],
      ),
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
