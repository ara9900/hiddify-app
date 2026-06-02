import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// خروج از برنامه یا (با تأیید چک‌باکس) خروج از حساب و پاک‌سازی نشست.
Future<void> showTikNetLogoutDialog(BuildContext parentContext, WidgetRef ref) async {
  var signOutAccount = false;

  await showDialog<void>(
    context: parentContext,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('خروج'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'با «خروج» فقط برنامه بسته می‌شود. برای ورود با حساب دیگر، گزینهٔ زیر را فعال کنید و «خروج از حساب کاربری» را بزنید.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TikNetColors.onSurfaceVariant,
                      ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: signOutAccount,
                  onChanged: (v) => setState(() => signOutAccount = v ?? false),
                  title: const Text('خروج از حساب کاربری'),
                  subtitle: const Text('توکن و اطلاعات حساب از اپ پاک می‌شود'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('بیخیال'),
              ),
              if (signOutAccount)
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await ref.read(authServiceProvider).logout();
                    if (parentContext.mounted) {
                      parentContext.go('/login');
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: TikNetColors.error),
                  child: const Text('خروج از حساب کاربری'),
                ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  SystemNavigator.pop();
                },
                child: const Text('خروج'),
              ),
            ],
          );
        },
      );
    },
  );
}
