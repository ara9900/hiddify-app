import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/model/tiknet_app_update_info.dart';
import 'package:hiddify/features/tiknet/service/tiknet_telemetry_service.dart';
import 'package:hiddify/features/tiknet/update/tiknet_app_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Full-screen update prompt when panel requires a newer APK (Android only).
class TikNetAppUpdateOverlay extends ConsumerStatefulWidget {
  const TikNetAppUpdateOverlay({super.key});

  @override
  ConsumerState<TikNetAppUpdateOverlay> createState() => _TikNetAppUpdateOverlayState();
}

class _TikNetAppUpdateOverlayState extends ConsumerState<TikNetAppUpdateOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (Platform.isAndroid) {
      ref.read(tikNetAppUpdateNotifierProvider.notifier).checkForUpdate();
    }
    ref.read(tikNetTelemetryServiceProvider).sendAppOpenOnce();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(Preferences.tikNetPanelBaseUrl, (prev, next) {
      if (next.isNotEmpty && next != (prev ?? '')) _check();
    });

    if (!Platform.isAndroid) return const SizedBox.shrink();

    final state = ref.watch(tikNetAppUpdateNotifierProvider);
    final notifier = ref.read(tikNetAppUpdateNotifierProvider.notifier);

    final TikNetAppUpdateInfo? info = switch (state) {
      TikNetAppUpdateAvailable(:final info) => info,
      TikNetAppUpdateDownloading(:final info) => info,
      TikNetAppUpdateError(:final info) => info,
      TikNetAppUpdateChecking(:final previousInfo) => previousInfo,
      _ => null,
    };

    if (info == null) return const SizedBox.shrink();

    final progress = state is TikNetAppUpdateDownloading ? state.progress : null;
    final error = state is TikNetAppUpdateError ? state.message : null;
    final busy = state is TikNetAppUpdateDownloading;

    return Material(
      color: Colors.black54,
      child: Center(
        child: PopScope(
          canPop: !notifier.isBlocking,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    info.force ? 'به‌روزرسانی اجباری' : 'نسخه جدید موجود است',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(12),
                  Text(
                    'نسخه ${info.versionName.isNotEmpty ? info.versionName : info.versionCode}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                  ),
                  if (info.changelog.isNotEmpty) ...[
                    const Gap(16),
                    Text(info.changelog, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (progress != null) ...[
                    const Gap(16),
                    LinearProgressIndicator(value: progress > 0 ? progress : null),
                    const Gap(8),
                    Text(
                      '${(progress * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                  if (error != null) ...[
                    const Gap(12),
                    Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const Gap(20),
                  FilledButton(
                    onPressed: busy ? null : () => notifier.downloadAndInstall(info),
                    child: Text(busy ? 'در حال دانلود...' : 'دانلود و نصب'),
                  ),
                  if (!info.force) ...[
                    const Gap(8),
                    TextButton(
                      onPressed: busy ? null : () => notifier.dismissOptional(info),
                      child: const Text('بعداً'),
                    ),
                  ] else ...[
                    const Gap(8),
                    Text(
                      'برای ادامه استفاده از اپ، نسخه جدید را نصب کنید.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                    ),
                  ],
                  if (error != null && !busy)
                    TextButton(
                      onPressed: () => notifier.checkForUpdate(forceRefresh: true),
                      child: const Text('تلاش مجدد'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
