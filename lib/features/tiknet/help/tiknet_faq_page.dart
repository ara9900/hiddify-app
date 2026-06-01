import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/model/tiknet_faq.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tikNetFaqProvider = FutureProvider<List<TikNetFaqItem>>((ref) async {
  final baseUrl = ref.watch(Preferences.tikNetPanelBaseUrl);
  if (baseUrl.isEmpty) return const [];
  try {
    return await ref.read(tikNetApiProvider).getFaq(baseUrl: baseUrl);
  } catch (_) {
    return const [];
  }
});

class TikNetFaqPage extends ConsumerWidget {
  const TikNetFaqPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final faqAsync = ref.watch(tikNetFaqProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('راهنما و سوالات'), centerTitle: true),
      body: faqAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text('بارگذاری راهنما ناموفق بود.', style: TextStyle(color: theme.colorScheme.error)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                'فعلاً سوالی ثبت نشده است.',
                style: theme.textTheme.bodyLarge?.copyWith(color: TikNetColors.onSurfaceVariant),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: Text(item.question, style: theme.textTheme.titleSmall),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(item.answer, style: theme.textTheme.bodyMedium),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
