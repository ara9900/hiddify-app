import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/service/tiknet_internet_troubleshoot_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_platform_diagnostics.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> showTikNetInternetTroubleshootSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TikNetColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _TikNetInternetTroubleshootSheet(),
  );
}

class _TikNetInternetTroubleshootSheet extends ConsumerStatefulWidget {
  const _TikNetInternetTroubleshootSheet();

  @override
  ConsumerState<_TikNetInternetTroubleshootSheet> createState() => _TikNetInternetTroubleshootSheetState();
}

class _TikNetInternetTroubleshootSheetState extends ConsumerState<_TikNetInternetTroubleshootSheet> {
  bool _running = false;
  List<TikNetTroubleshootItem>? _items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _items = null;
    });
    try {
      final items = await ref.read(tikNetInternetTroubleshootServiceProvider).runChecks();
      if (mounted) setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _openSettings(TikNetTroubleshootSettingsTarget target) async {
    final key = switch (target) {
      TikNetTroubleshootSettingsTarget.date => 'date',
      TikNetTroubleshootSettingsTarget.vpn => 'vpn',
      TikNetTroubleshootSettingsTarget.apn => 'apn',
      TikNetTroubleshootSettingsTarget.privateDns => 'private_dns',
      TikNetTroubleshootSettingsTarget.wireless => 'wireless',
      TikNetTroubleshootSettingsTarget.battery => 'battery',
      TikNetTroubleshootSettingsTarget.airplane => 'airplane',
      TikNetTroubleshootSettingsTarget.none => null,
    };
    if (key == null) return;
    final ok = await TikNetPlatformDiagnostics.openSystemSettings(key);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('باز کردن تنظیمات ممکن نشد.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const Gap(10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: TikNetColors.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'عیب‌یابی اینترنت گوشی',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: _running ? null : _run,
                    tooltip: 'بررسی مجدد',
                    icon: _running
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'مواردی که معمولاً اینترنت یا VPN را خراب می‌کنند بررسی می‌شوند.',
                style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
              ),
            ),
            const Gap(12),
            Expanded(
              child: _running && _items == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _items?.length ?? 0,
                      separatorBuilder: (_, _) => const Gap(8),
                      itemBuilder: (context, index) {
                        final item = _items![index];
                        return _TroubleshootTile(
                          item: item,
                          onOpenSettings: item.settingsTarget == TikNetTroubleshootSettingsTarget.none
                              ? null
                              : () => _openSettings(item.settingsTarget),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TroubleshootTile extends StatelessWidget {
  const _TroubleshootTile({required this.item, this.onOpenSettings});

  final TikNetTroubleshootItem item;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (item.status) {
      TikNetTroubleshootStatus.ok => (Icons.check_circle_rounded, TikNetColors.connected),
      TikNetTroubleshootStatus.fail => (Icons.cancel_rounded, TikNetColors.error),
      TikNetTroubleshootStatus.warn => (Icons.warning_amber_rounded, Colors.orange.shade700),
      TikNetTroubleshootStatus.info => (Icons.info_outline_rounded, TikNetColors.onSurfaceVariant),
    };

    return Material(
      color: TikNetColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap(4),
                  Text(
                    item.detail,
                    style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant, height: 1.35),
                  ),
                  if (onOpenSettings != null) ...[
                    const Gap(8),
                    TextButton(
                      onPressed: onOpenSettings,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('باز کردن تنظیمات'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
