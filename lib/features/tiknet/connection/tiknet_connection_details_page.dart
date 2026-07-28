import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/tiknet/connection/tiknet_connection_stats_provider.dart';
import 'package:hiddify/features/tiknet/connection/tiknet_connection_uptime_provider.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/server_catalog_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_node_pings_notifier.dart';
import 'package:hiddify/features/tiknet/service/tiknet_smart_connect.dart';
import 'package:hiddify/features/tiknet/widgets/tiknet_ping_chip.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Dedicated tab for live connection / traffic / IP details.
class TikNetConnectionDetailsPage extends ConsumerWidget {
  const TikNetConnectionDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final isConnected = connectionStatus.valueOrNull is Connected;
    final isBusy = connectionStatus.valueOrNull is Connecting || connectionStatus.valueOrNull is Disconnecting;
    final stats = ref.watch(tiknetConnectionStatsProvider).valueOrNull;
    final uptime = ref.watch(tiknetConnectionUptimeProvider).valueOrNull;
    final ipAsync = ref.watch(ipInfoNotifierProvider);
    final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;

    final selected = ref.watch(selectedServerProvider);
    final catalog = ref.watch(serverCatalogProvider).valueOrNull;
    final personalNodes = ref.watch(personalOutboundProvider).valueOrNull;
    final nodePings = ref.watch(tikNetNodePingsProvider).valueOrNull;
    final smartLocked = ref.watch(Preferences.tikNetSmartLockedTag);
    final smartPicking = ref.watch(tikNetSmartPickingProvider);
    final serverInfo = resolveSelectedServerInfo(
      selected: selected,
      catalog: catalog,
      personalCatalog: personalNodes?.catalog,
      personalNodePings: nodePings,
      smartLockedTag: smartLocked,
    );

    final statusLabel = switch (connectionStatus) {
      AsyncData(value: Connected()) when smartPicking => 'انتخاب بهترین سرور…',
      AsyncData(value: Connected()) => 'متصل',
      AsyncData(value: Connecting()) => 'در حال اتصال…',
      AsyncData(value: Disconnecting()) => 'در حال قطع…',
      _ => 'قطع شده',
    };
    final statusColor = switch (connectionStatus) {
      AsyncData(value: Connected()) when smartPicking => TikNetColors.connecting,
      AsyncData(value: Connected()) => TikNetColors.connected,
      AsyncData(value: Connecting()) || AsyncData(value: Disconnecting()) => TikNetColors.connecting,
      _ => TikNetColors.disconnected,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('جزئیات اتصال'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tiknetConnectionStatsProvider);
            await ref.read(ipInfoNotifierProvider.notifier).refresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _StatusHero(
                label: statusLabel,
                color: statusColor,
                isConnected: isConnected,
                isBusy: isBusy,
                uptime: uptime,
              ),
              const Gap(16),
              _SectionCard(
                title: 'سرور و مسیر',
                child: Column(
                  children: [
                    _DetailRow(icon: Icons.dns_rounded, label: 'سرور انتخابی', value: serverInfo.title),
                    const _Divider(),
                    _DetailRow(icon: Icons.info_outline_rounded, label: 'توضیح', value: serverInfo.subtitle),
                    if (serverInfo.pingLabel != null && serverInfo.pingColor != null) ...[
                      const _Divider(),
                      Row(
                        children: [
                          const Icon(Icons.speed_rounded, size: 18, color: TikNetColors.onSurfaceVariant),
                          const Gap(12),
                          Expanded(
                            child: Text(
                              'پینگ سرور',
                              style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                            ),
                          ),
                          TikNetPingChip(
                            label: serverInfo.pingLabel!,
                            color: serverInfo.pingColor!,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                    if ((stats?.outboundTag ?? '').isNotEmpty) ...[
                      const _Divider(),
                      _DetailRow(icon: Icons.route_rounded, label: 'مسیر خروجی', value: stats!.outboundTag),
                    ],
                    if (activeProxy != null && (activeProxy.tagDisplay.isNotEmpty || activeProxy.type.isNotEmpty)) ...[
                      if (activeProxy.tagDisplay.isNotEmpty) ...[
                        const _Divider(),
                        _DetailRow(icon: Icons.label_outline_rounded, label: 'پروکسی فعال', value: activeProxy.tagDisplay),
                      ],
                      if (activeProxy.type.isNotEmpty) ...[
                        const _Divider(),
                        _DetailRow(icon: Icons.category_outlined, label: 'نوع پروتکل', value: activeProxy.type),
                      ],
                      if (activeProxy.urlTestDelay > 0) ...[
                        const _Divider(),
                        _DetailRow(
                          icon: Icons.timer_outlined,
                          label: 'تأخیر هسته',
                          value: '${toPersianDigits('${activeProxy.urlTestDelay}')} ms',
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const Gap(16),
              _SectionCard(
                title: 'آی‌پی خروجی',
                trailing: IconButton(
                  tooltip: 'بررسی مجدد آی‌پی',
                  onPressed: () => ref.read(ipInfoNotifierProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                child: switch (ipAsync) {
                  AsyncData(:final value) => Column(
                      children: [
                        Row(
                          children: [
                            IPCountryFlag(countryCode: value.countryCode, size: 40),
                            const Gap(14),
                            Expanded(
                              child: Text(
                                persianCountryName(value.countryCode),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        const _Divider(),
                        const Gap(12),
                        Row(
                          children: [
                            const Icon(Icons.public_rounded, size: 18, color: TikNetColors.onSurfaceVariant),
                            const Gap(12),
                            Expanded(
                              child: Text(
                                'آی‌پی خروجی',
                                style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                              ),
                            ),
                            Flexible(
                              child: IPText(
                                ip: value.ip,
                                onLongPress: () => ref.read(ipInfoNotifierProvider.notifier).refresh(),
                                constrained: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  AsyncLoading() => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  AsyncError(:final error) => _IpErrorState(
                      message: error is ServiceNotRunning
                          ? 'برای نمایش آی‌پی، ابتدا متصل شوید'
                          : error is UnknownIp
                              ? 'آی‌پی هنوز مشخص نیست — برای بررسی بزنید'
                              : 'خطا در دریافت آی‌پی',
                      onRetry: () => ref.read(ipInfoNotifierProvider.notifier).refresh(),
                    ),
                  _ => _IpErrorState(
                      message: 'آی‌پی در دسترس نیست',
                      onRetry: () => ref.read(ipInfoNotifierProvider.notifier).refresh(),
                    ),
                },
              ),
              const Gap(16),
              _SectionCard(
                title: 'سرعت لحظه‌ای',
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.arrow_downward_rounded,
                        iconColor: TikNetColors.connected,
                        label: 'دانلود',
                        value: isConnected && stats != null ? toPersianDigits(stats.downlink.speed()) : '—',
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.arrow_upward_rounded,
                        iconColor: TikNetColors.primary,
                        label: 'آپلود',
                        value: isConnected && stats != null ? toPersianDigits(stats.uplink.speed()) : '—',
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(16),
              _SectionCard(
                title: 'ترافیک این نشست',
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.download_rounded,
                      label: 'حجم دانلود',
                      value: isConnected && stats != null ? toPersianDigits(stats.downlinkTotal.size()) : '—',
                    ),
                    const _Divider(),
                    _DetailRow(
                      icon: Icons.upload_rounded,
                      label: 'حجم آپلود',
                      value: isConnected && stats != null ? toPersianDigits(stats.uplinkTotal.size()) : '—',
                    ),
                    const _Divider(),
                    _DetailRow(
                      icon: Icons.swap_vert_rounded,
                      label: 'مجموع نشست',
                      value: isConnected && stats != null
                          ? toPersianDigits((stats.uplinkTotal + stats.downlinkTotal).size())
                          : '—',
                    ),
                  ],
                ),
              ),
              const Gap(16),
              _SectionCard(
                title: 'وضعیت هسته',
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.schedule_rounded,
                      label: 'مدت اتصال',
                      value: isConnected ? (uptime ?? '—') : '—',
                    ),
                    const _Divider(),
                    _DetailRow(
                      icon: Icons.call_made_rounded,
                      label: 'اتصالات خروجی',
                      value: isConnected && stats != null
                          ? toPersianDigits('${stats.connectionsOut}')
                          : '—',
                    ),
                    const _Divider(),
                    _DetailRow(
                      icon: Icons.call_received_rounded,
                      label: 'اتصالات ورودی',
                      value: isConnected && stats != null
                          ? toPersianDigits('${stats.connectionsIn}')
                          : '—',
                    ),
                    const _Divider(),
                    _DetailRow(
                      icon: Icons.memory_rounded,
                      label: 'مصرف حافظه هسته',
                      value: isConnected && stats != null && stats.memory > 0
                          ? toPersianDigits(stats.memory.size())
                          : '—',
                    ),
                  ],
                ),
              ),
              if (!isConnected) ...[
                const Gap(20),
                Text(
                  'پس از اتصال، سرعت، آی‌پی خروجی و آمار نشست اینجا نمایش داده می‌شود.',
                  textAlign: TextAlign.center,
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

/// ISO country code → Persian display name.
String persianCountryName(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  if (c.isEmpty) return 'نامشخص';
  return switch (c) {
    'DE' => 'آلمان',
    'FR' => 'فرانسه',
    'NL' => 'هلند',
    'US' => 'آمریکا',
    'GB' || 'UK' => 'انگلستان',
    'TR' => 'ترکیه',
    'AE' => 'امارات',
    'IR' => 'ایران',
    'CA' => 'کانادا',
    'FI' => 'فنلاند',
    'SE' => 'سوئد',
    'NO' => 'نروژ',
    'PL' => 'لهستان',
    'IT' => 'ایتالیا',
    'ES' => 'اسپانیا',
    'AT' => 'اتریش',
    'CH' => 'سوئیس',
    'BE' => 'بلژیک',
    'CZ' => 'چک',
    'RU' => 'روسیه',
    'JP' => 'ژاپن',
    'SG' => 'سنگاپور',
    'HK' => 'هنگ‌کنگ',
    'IN' => 'هند',
    'AU' => 'استرالیا',
    'BR' => 'برزیل',
    'KR' => 'کره جنوبی',
    'CN' => 'چین',
    'UA' => 'اوکراین',
    'RO' => 'رومانی',
    'BG' => 'بلغارستان',
    'PT' => 'پرتغال',
    'IE' => 'ایرلند',
    'DK' => 'دانمارک',
    'LT' => 'لیتوانی',
    'LV' => 'لتونی',
    'EE' => 'استونی',
    'MD' => 'مولداوی',
    'KZ' => 'قزاقستان',
    'AM' => 'ارمنستان',
    'GE' => 'گرجستان',
    'AZ' => 'آذربایجان',
    'IQ' => 'عراق',
    'SA' => 'عربستان',
    'QA' => 'قطر',
    'KW' => 'کویت',
    'MY' => 'مالزی',
    'TH' => 'تایلند',
    'ID' => 'اندونزی',
    'VN' => 'ویتنام',
    'PH' => 'فیلیپین',
    'NZ' => 'نیوزیلند',
    'MX' => 'مکزیک',
    'AR' => 'آرژانتین',
    'CL' => 'شیلی',
    'ZA' => 'آفریقای جنوبی',
    'EG' => 'مصر',
    'IL' => 'اسرائیل',
    'CY' => 'قبرس',
    'GR' => 'یونان',
    'HU' => 'مجارستان',
    'SK' => 'اسلواکی',
    'SI' => 'اسلوونی',
    'HR' => 'کرواسی',
    'RS' => 'صربستان',
    'BA' => 'بوسنی',
    'MK' => 'مقدونیه',
    'AL' => 'آلبانی',
    'LU' => 'لوکزامبورگ',
    'IS' => 'ایسلند',
    'MT' => 'مالت',
    'TW' => 'تایوان',
    'MO' => 'ماکائو',
    _ => c,
  };
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.label,
    required this.color,
    required this.isConnected,
    required this.isBusy,
    this.uptime,
  });

  final String label;
  final Color color;
  final bool isConnected;
  final bool isBusy;
  final String? uptime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [color.withValues(alpha: 0.18), TikNetColors.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: isConnected ? 0.5 : 0.25), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.2)),
            child: Icon(
              isConnected
                  ? Icons.analytics_rounded
                  : (isBusy ? Icons.sync_rounded : Icons.analytics_outlined),
              color: color,
              size: 28,
            ),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color),
                ),
                const Gap(4),
                Text(
                  isConnected
                      ? 'مدت نشست: ${uptime ?? '—'}'
                      : 'برای دیدن آمار زنده، از تب اتصال وصل شوید',
                  style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const Gap(14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: TikNetColors.surfaceVariant.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TikNetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const Gap(10),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant)),
          const Gap(4),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: TikNetColors.onSurfaceVariant),
        const Gap(12),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant)),
        ),
        const Gap(8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: TikNetColors.border),
      );
}

class _IpErrorState extends StatelessWidget {
  const _IpErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
        ),
        const Gap(12),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('بررسی آی‌پی'),
        ),
      ],
    );
  }
}
