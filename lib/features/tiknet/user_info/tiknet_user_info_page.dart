import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class TikNetUserInfoPage extends ConsumerWidget {
  const TikNetUserInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final panelUrl = ref.watch(Preferences.tikNetPanelBaseUrl);
    final token = ref.watch(Preferences.tikNetAccessToken);

    if (panelUrl.isEmpty || token.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My account')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My account')),
      body: FutureBuilder<TikNetUserInfo>(
        future: ref.read(tikNetApiProvider).getMe(baseUrl: panelUrl, accessToken: token),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load: ${snapshot.error}', textAlign: TextAlign.center),
                    const Gap(16),
                    FilledButton(onPressed: () => context.go('/home'), child: const Text('Back')),
                  ],
                ),
              ),
            );
          }
          final info = snapshot.data!;
          final dateFormat = DateFormat.yMMMd();

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(theme, 'Username', info.username),
                      if (info.fullName != null && info.fullName!.isNotEmpty) _row(theme, 'Name', info.fullName!),
                      _row(theme, 'Expiry date', info.expireDate != null ? dateFormat.format(info.expireDate!) : '—'),
                      _row(theme, 'Subscription', info.hasSubscription ? 'Active' : 'Inactive'),
                    ],
                  ),
                ),
              ),
              const Gap(24),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(Preferences.tikNetAccessToken.notifier).update('');
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
