import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';

/// TikNet: فیلتر اپ‌ها (Split Tunnel) — لیست اپ‌های نصب‌شده با سوییچ فعال/غیرفعال، جستجو، تم دارک، RTL.
class TikNetAppFilterPage extends HookConsumerWidget {
  const TikNetAppFilterPage({super.key});

  static Future<Set<AppPackageInfo>> _getApps(bool hideSystem) async {
    if (!PlatformUtils.isAndroid) return {};
    return (await InstalledApps.getInstalledApps(hideSystem, true))
        .map((e) => AppPackageInfo(packageName: e.packageName, name: e.name, icon: e.icon))
        .toSet();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final searchController = useTextEditingController();
    final searchQuery = useState('');

    final mode = PerAppProxyMode.include.toAppProxy();
    useEffect(() {
      if (ref.read(Preferences.perAppProxyMode) == PerAppProxyMode.off) {
        ref.read(Preferences.perAppProxyMode.notifier).update(PerAppProxyMode.include);
      }
      return null;
    }, []);

    final selectedApps = ref.watch(PerAppProxyProvider(mode));

    final asyncApps = useFuture(useMemoized(() => _getApps(false)));

    final filteredList = useMemoized(() {
      if (!asyncApps.hasData || selectedApps is! AsyncData) return <AppPackageInfo>[];
      final list = asyncApps.requireData.toList()..sort((a, b) => a.name.compareTo(b.name));
      final q = searchQuery.value.trim().toLowerCase();
      if (q.isEmpty) return list;
      return list.where((e) => e.name.toLowerCase().contains(q) || e.packageName.toLowerCase().contains(q)).toList();
    }, [asyncApps.connectionState, asyncApps.hasData, asyncApps.requireData, searchQuery.value, selectedApps]);

    if (!PlatformUtils.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('فیلتر اپ‌ها')),
        body: Center(
          child: Text(
            'فقط در اندروید در دسترس است.',
            style: theme.textTheme.bodyLarge?.copyWith(color: TikNetColors.onSurfaceVariant),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('فیلتر اپ‌ها'),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: searchController,
              onChanged: (v) => searchQuery.value = v,
              decoration: InputDecoration(
                hintText: 'جستجو بین اپ‌ها',
                hintStyle: TextStyle(color: TikNetColors.onSurfaceVariant.withValues(alpha: 0.7)),
                prefixIcon: Icon(Icons.search_rounded, color: TikNetColors.onSurfaceVariant),
                filled: true,
                fillColor: TikNetColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Expanded(
            child: asyncApps.when(
              data: (_) => selectedApps.when(
                data: (_) {
                  if (filteredList.isEmpty) {
                    return Center(
                      child: Text(
                        searchQuery.value.trim().isEmpty ? 'اپی یافت نشد.' : 'نتیجه‌ای برای جستجو یافت نشد.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final app = filteredList[index];
                      final flag = selectedApps.requireValue[app.packageName];
                      final isOn = flag != null &&
                          (PkgFlag.userSelection.check(flag) ||
                              (PkgFlag.autoSelection.check(flag) && !PkgFlag.forceDeselection.check(flag)));
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: app.icon == null
                              ? CircleAvatar(
                                  backgroundColor: TikNetColors.surfaceVariant,
                                  child: Icon(Icons.app_rounded, color: TikNetColors.onSurfaceVariant),
                                )
                              : CircleAvatar(
                                  backgroundImage: MemoryImage(app.icon!),
                                  radius: 24,
                                ),
                          title: Text(
                            app.name,
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Switch.adaptive(
                            value: isOn,
                            onChanged: (_) =>
                                ref.read(PerAppProxyProvider(mode).notifier).updatePkg(app.packageName),
                            activeColor: TikNetColors.primary,
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'خطا در بارگذاری لیست.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'خطا در بارگذاری اپ‌ها.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
