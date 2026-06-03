import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/server_catalog_provider.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/widgets/tiknet_country_flag.dart';
import 'package:hiddify/features/tiknet/widgets/tiknet_ping_chip.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetServerPickerSheet extends ConsumerWidget {
  const TikNetServerPickerSheet({super.key, this.scrollController});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: TikNetColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: TikNetColors.border)),
          ),
          child: TikNetServerPickerSheet(scrollController: scrollController),
        ),
      ),
    );
  }

  static String tierTitle(String tier) => switch (tier) {
        'vip' => 'VIP',
        'normal' => 'معمولی',
        _ => 'رایگان',
      };

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalogAsync = ref.watch(serverCatalogProvider);
    final personalAsync = ref.watch(personalOutboundProvider);
    final selected = ref.watch(selectedServerProvider);
    final sync = ref.read(syncServiceProvider);
    final vpnConnected = ref.watch(connectionNotifierProvider).valueOrNull is Connected;

    return Column(
      children: [
        const Gap(10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: TikNetColors.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('انتخاب سرور', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const Gap(4),
                    Text(
                      vpnConnected ? 'VPN متصل است — تغییر سرور اتصال را قطع می‌کند' : 'سرور مورد نظر را انتخاب کنید',
                      style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        const Divider(height: 1, color: TikNetColors.border),
        Expanded(
          child: catalogAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('خطا در بارگذاری سرورها.', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ),
            data: (catalog) {
              final personalState = personalAsync.valueOrNull;
              final personalCatalog = personalState?.catalog;
              final nodePings = personalState?.nodePings ?? const {};
              final personalOnly = catalog.displayMode == TikNetServerDisplayMode.personalOnly;
              final groups = catalog.groupedByTier();
              const tierOrder = ['free', 'normal', 'vip'];

              bool isDefaultPersonalSelected() =>
                  selected.isPersonal &&
                  selected.catalogId == null &&
                  selected.personalKind == TikNetPersonalPickKind.defaultAuto;

              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (catalog.showPersonal && !personalOnly) ...[
                    _ServerRow(
                      title: 'اشتراک من',
                      subtitle: 'کانفیگ اختصاصی حساب شما',
                      personal: true,
                      selected: isDefaultPersonalSelected(),
                      enabled: true,
                      onTap: () => _select(context, ref, sync, personalDefaultSelection()),
                    ),
                  ],
                  if (catalog.showPersonal && personalOnly) ...[
                    const _SectionHeader(title: 'اشتراک اختصاصی'),
                    _ServerRow(
                      title: 'پیش‌فرض اشتراک',
                      subtitle: 'همان انتخاب پیش‌فرض در کانفیگ',
                      personal: true,
                      selected: isDefaultPersonalSelected(),
                      enabled: true,
                      onTap: () => _select(context, ref, sync, personalDefaultSelection()),
                    ),
                    if (personalAsync.isLoading && (personalCatalog == null || personalCatalog.isEmpty))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (personalCatalog != null) ...[
                      for (final mode in personalCatalog.autoModes)
                        _ServerRow(
                          title: mode.title,
                          subtitle: mode.subtitle,
                          personal: true,
                          selected: selected.isPersonal &&
                              selected.personalKind == mode.kind &&
                              selected.personalTag == mode.tag,
                          enabled: true,
                          onTap: () => _select(
                            context,
                            ref,
                            sync,
                            (
                              isPersonal: true,
                              catalogId: null,
                              personalKind: mode.kind,
                              personalTag: mode.tag,
                              personalGroupTag: mode.groupTag,
                            ),
                          ),
                        ),
                      if (personalCatalog.nodes.isNotEmpty) ...[
                        const _SectionHeader(title: 'سرورها'),
                        ...personalCatalog.nodes.map((node) {
                          final ping = nodePings[node.tag];
                          return _ServerRow(
                            title: node.label,
                            subtitle: 'انتخاب مستقیم این کانفیگ',
                            personal: true,
                            selected: selected.isPersonal &&
                                selected.personalKind == TikNetPersonalPickKind.proxy &&
                                selected.personalTag == node.tag,
                            enabled: true,
                            pingLabel: ping?.pingLabel,
                            pingColor: ping?.pingColor,
                            isUnreachableFromDevice: ping?.state == TikNetClientPingState.unreachable,
                            onTap: () => _select(
                              context,
                              ref,
                              sync,
                              (
                                isPersonal: true,
                                catalogId: null,
                                personalKind: TikNetPersonalPickKind.proxy,
                                personalTag: node.tag,
                                personalGroupTag: node.groupTag,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                    if (personalCatalog != null &&
                        personalCatalog.isEmpty &&
                        !personalAsync.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'لیست کانفیگ از اشتراک خوانده نشد. یک‌بار «بروزرسانی» بزنید.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: TikNetColors.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                  ],
                  if (catalog.showCatalog)
                    for (final tier in tierOrder)
                      if (groups[tier]?.isNotEmpty == true) ...[
                        _SectionHeader(title: tierTitle(tier)),
                        ...groups[tier]!.map(
                          (s) => _ServerRow(
                            title: s.name,
                            subtitle: [s.countryLabel, s.tierLabel].where((e) => e.isNotEmpty).join(' · '),
                            countryCode: s.countryCode,
                            selected: !selected.isPersonal && selected.catalogId == s.id,
                            enabled: s.accessible,
                            locked: !s.accessible,
                            pingLabel: s.pingLabel,
                            pingColor: s.pingColor,
                            isUnreachableFromDevice: s.isUnreachableFromDevice,
                            onTap: s.accessible
                                ? () => _select(
                                      context,
                                      ref,
                                      sync,
                                      (
                                        isPersonal: false,
                                        catalogId: s.id,
                                        personalKind: TikNetPersonalPickKind.defaultAuto,
                                        personalTag: null,
                                        personalGroupTag: null,
                                      ),
                                    )
                                : null,
                          ),
                        ),
                      ],
                  if (!catalog.showPersonal && !catalog.showCatalog)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('سروری برای نمایش تنظیم نشده است.', textAlign: TextAlign.center),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    SyncService sync,
    TikNetServerSelection selection,
  ) async {
    Navigator.pop(context);
    await sync.setSelectedServer(selection);
    ref.invalidate(serverCatalogProvider);
    ref.invalidate(personalOutboundProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('در حال اعمال کانفیگ سرور...'), behavior: SnackBarBehavior.floating),
    );
    try {
      final ok = await sync.applySelectedServerConfig();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'سرور انتخاب شد.' : 'اعمال کانفیگ ناموفق بود.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on SyncTokenExpiredException {
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, right: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: TikNetColors.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    this.countryCode,
    this.personal = false,
    this.locked = false,
    this.pingLabel,
    this.pingColor,
    this.isUnreachableFromDevice = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? countryCode;
  final bool personal;
  final bool selected;
  final bool enabled;
  final bool locked;
  final String? pingLabel;
  final Color? pingColor;
  final bool isUnreachableFromDevice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected ? TikNetColors.primary : TikNetColors.border;
    final bg = selected ? TikNetColors.primary.withValues(alpha: 0.1) : TikNetColors.surfaceVariant.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  TikNetCountryFlag(countryCode: countryCode, personal: personal, size: 44),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const Gap(2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (locked)
                    const Icon(Icons.lock_outline_rounded, color: TikNetColors.onSurfaceVariant, size: 20)
                  else if (pingLabel != null && pingColor != null) ...[
                    TikNetPingChip(label: pingLabel!, color: pingColor!, compact: true),
                    const Gap(8),
                  ],
                  if (selected)
                    const Icon(Icons.check_circle_rounded, color: TikNetColors.primary, size: 22)
                  else if (isUnreachableFromDevice)
                    Icon(Icons.cloud_off_rounded, color: TikNetColors.error.withValues(alpha: 0.8), size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TikNetServerSelectorCard extends ConsumerWidget {
  const TikNetServerSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedServerProvider);
    final catalog = ref.watch(serverCatalogProvider).valueOrNull;
    final personalNodes = ref.watch(personalOutboundProvider).valueOrNull;
    final info = resolveSelectedServerInfo(
      selected: selected,
      catalog: catalog,
      personalCatalog: personalNodes?.catalog,
      personalNodePings: personalNodes?.nodePings,
    );
    final vpnConnected = ref.watch(connectionNotifierProvider).valueOrNull is Connected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          ref.invalidate(serverCatalogProvider);
          ref.invalidate(personalOutboundProvider);
          TikNetServerPickerSheet.show(context);
        },
        child: Ink(
          decoration: BoxDecoration(
            color: TikNetColors.surfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TikNetColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TikNetCountryFlag(
                  countryCode: info.countryCode,
                  personal: info.personal,
                  size: 48,
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'سرور انتخابی',
                            style: theme.textTheme.labelMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                          ),
                          const Spacer(),
                          if (vpnConnected)
                            const _MiniStatusPill(label: 'VPN روشن', color: TikNetColors.connected)
                          else
                            const _MiniStatusPill(label: 'VPN خاموش', color: TikNetColors.disconnected),
                        ],
                      ),
                      const Gap(6),
                      Text(
                        info.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (info.subtitle.isNotEmpty) ...[
                        const Gap(2),
                        Text(
                          info.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const Gap(8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (info.pingLabel != null && info.pingColor != null)
                      TikNetPingChip(label: info.pingLabel!, color: info.pingColor!, compact: true),
                    const Gap(8),
                    const Icon(Icons.unfold_more_rounded, color: TikNetColors.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  const _MiniStatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const Gap(5),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
