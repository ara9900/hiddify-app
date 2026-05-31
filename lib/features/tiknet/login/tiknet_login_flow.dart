import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shared post-auth steps: sync config from panel, then navigate home.
Future<void> completeTikNetLoginFlow(WidgetRef ref, BuildContext context) async {
  await ref.read(Preferences.introCompleted.notifier).update(true);
  await ref.read(Preferences.startedByUser.notifier).update(false);
  await ref.read(connectionNotifierProvider.notifier).abortConnection();

  final sync = ref.read(syncServiceProvider);
  try {
    final synced = await sync.syncAllAndApplyProfile();
    if (context.mounted && !synced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ورود موفق بود؛ دریافت کانفیگ از پنل ناموفق. از «حساب من» → بروزرسانی دوباره تلاش کنید.'),
        ),
      );
    }
  } on SyncTokenExpiredException {
    if (context.mounted) context.go('/login');
    return;
  }

  if (context.mounted) context.go('/home');
}

Future<void> performTikNetLogin({
  required WidgetRef ref,
  required BuildContext context,
  required String username,
  required String password,
  String? panelBaseUrl,
}) async {
  final auth = ref.read(authServiceProvider);
  await auth.login(username, password, panelBaseUrl: panelBaseUrl);
  if (context.mounted) await completeTikNetLoginFlow(ref, context);
}
