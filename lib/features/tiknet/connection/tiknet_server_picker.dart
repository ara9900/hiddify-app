import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/server_catalog_provider.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetServerPickerSheet extends ConsumerWidget {
  const TikNetServerPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TikNetColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: TikNetServerPickerSheet(),
      ),
    );
  }

  static String tierTitle(String tier) => switch (tier) {
        'vip' => 'VIP',
        'normal' => 'معمولی',
        _ => 'رایگان',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalogAsync = ref.watch(serverCatalogProvider);
    final selected = ref.watch(selectedServerProvider);
    final sync = ref.read(syncServiceProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'انتخاب سرور',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          const Divider(height: 1, color: TikNetColors.border),
          Flexible(
            child: catalogAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'خطا در بارگذاری لیست سرورها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              data: (catalog) {
                final groups = catalog.groupedByTier();
                const tierOrder = ['free', 'normal', 'vip'];
                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  children: [
                    if (catalog.personalAvailable)
                      _ServerTile(
                        title: 'اشتراک من',
                        subtitle: 'کانفیگ اختصاصی حساب شما',
                        selected: selected.isPersonal,
                        enabled: true,
                        onTap: () => _select(context, ref, sync, (isPersonal: true, catalogId: null)),
                      ),
                    for (final tier in tierOrder)
                      if (groups[tier]?.isNotEmpty == true) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                          child: Text(
                            tierTitle(tier),
                            style: theme.textTheme.titleSmall?.copyWith(color: TikNetColors.primary),
                          ),
                        ),
                        ...groups[tier]!.map(
                          (s) => _ServerTile(
                            title: s.name,
                            subtitle: [s.countryLabel, s.tierLabel].where((e) => e.isNotEmpty).join(' · '),
                            selected: !selected.isPersonal && selected.catalogId == s.id,
                            enabled: s.accessible,
                            locked: !s.accessible,
                            onTap: s.accessible
                                ? () => _select(context, ref, sync, (isPersonal: false, catalogId: s.id))
                                : null,
                          ),
                        ),
                      ],
                    if (!catalog.personalAvailable && catalog.servers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('سروری در پنل ثبت نشده است.', textAlign: TextAlign.center),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
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
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('در حال اعمال کانفیگ سرور...')),
    );
    try {
      final ok = await sync.applySelectedServerConfig();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'سرور انتخاب شد.' : 'اعمال کانفیگ ناموفق بود.')),
      );
    } on SyncTokenExpiredException {
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    this.locked = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: selected ? TikNetColors.primary.withValues(alpha: 0.15) : null,
      leading: Icon(
        locked ? Icons.lock_outline_rounded : Icons.public_rounded,
        color: selected ? TikNetColors.primary : TikNetColors.onSurfaceVariant,
      ),
      title: Text(title, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: TikNetColors.onSurfaceVariant, fontSize: 12)),
      trailing: selected ? const Icon(Icons.check_circle_rounded, color: TikNetColors.primary) : null,
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

    var label = 'اشتراک من';
    var sub = 'کانفیگ حساب شما';
    if (!selected.isPersonal && selected.catalogId != null) {
      TikNetServerEntry? match;
      for (final s in catalog?.servers ?? const <TikNetServerEntry>[]) {
        if (s.id == selected.catalogId) {
          match = s;
          break;
        }
      }
      if (match != null) {
        label = match.name;
        sub = [match.countryLabel, match.tierLabel].where((e) => e.isNotEmpty).join(' · ');
      } else {
        label = 'سرور #${selected.catalogId}';
        sub = 'کاتالوگ';
      }
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => TikNetServerPickerSheet.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.dns_rounded, color: TikNetColors.primary),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('سرور', style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant)),
                    Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (sub.isNotEmpty)
                      Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded, color: TikNetColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
