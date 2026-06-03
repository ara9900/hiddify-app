import 'package:flutter/material.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shows app version from [pubspec.yaml] (e.g. «نسخه 4.2.9»).
class TikNetAppVersionLabel extends ConsumerWidget {
  const TikNetAppVersionLabel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(appInfoProvider);
    return async.when(
      data: (info) {
        final text = compact ? 'v${info.version}' : 'نسخه ${info.version}';
        return Text(
          text,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(
            color: TikNetColors.onSurfaceVariant,
            fontWeight: compact ? FontWeight.w600 : null,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
