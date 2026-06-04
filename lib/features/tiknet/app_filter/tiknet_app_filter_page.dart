import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_page.dart';
import 'package:hiddify/features/tiknet/widgets/tiknet_loading_view.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';

/// TikNet tab «فیلتر اپ‌ها» — لیست اپ‌ها، لودینگ برند، اپ‌های روشن‌شده بالای لیست.
class TikNetAppFilterPage extends HookConsumerWidget {
  const TikNetAppFilterPage({super.key});

  static Future<Set<AppPackageInfo>> _getApps(bool hideSystem) async {
    if (!PlatformUtils.isAndroid) return {};
    return (await InstalledApps.getInstalledApps(hideSystem, true))
        .map((e) => AppPackageInfo(packageName: e.packageName, name: e.name, icon: e.icon))
        .toSet();
  }

  static bool _isSwitchOn(Map<String, int> selected, String packageName) {
    final flag = selected[packageName];
    if (flag == null) return false;
    return PkgFlag.userSelection.check(flag) ||
        (PkgFlag.autoSelection.check(flag) && !PkgFlag.forceDeselection.check(flag));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final searchController = useTextEditingController();
    final searchQuery = useState('');
    final sortTick = useState(0);

    final mode = ref.watch(Preferences.perAppProxyMode).toAppProxy() ?? PerAppProxyMode.include.toAppProxy();
    final perAppEnabled = ref.watch(Preferences.perAppProxyMode).enabled;
    final selectedApps = ref.watch(PerAppProxyProvider(mode));
    final asyncApps = useFuture(useMemoized(() => _getApps(false)));

    final selectedMap = selectedApps.valueOrNull ?? const <String, int>{};

    final displayList = useMemoized(() {
      if (!asyncApps.hasData) return <AppPackageInfo>[];
      final list = asyncApps.requireData.toList();
      if (perAppEnabled) {
        list.sort(
          (a, b) => PerAppProxyPage.sortPriority(a, selectedMap).compareTo(
            PerAppProxyPage.sortPriority(b, selectedMap),
          ),
        );
      } else {
        list.sort((a, b) => a.name.compareTo(b.name));
      }
      final q = searchQuery.value.trim().toLowerCase();
      if (q.isEmpty) return list;
      return list
          .where((e) => e.name.toLowerCase().contains(q) || e.packageName.toLowerCase().contains(q))
          .toList();
    }, [
      asyncApps.connectionState,
      asyncApps.hasData,
      searchQuery.value,
      perAppEnabled,
      selectedMap,
      sortTick.value,
    ]);

    final pinnedApps = perAppEnabled
        ? displayList.where((p) => PerAppProxyPage.isManuallyEnabled(selectedMap, p.packageName)).toList()
        : <AppPackageInfo>[];

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

    final appsLoading = asyncApps.connectionState == ConnectionState.waiting || !asyncApps.hasData;

    return Scaffold(
      backgroundColor: TikNetColors.background,
      appBar: AppBar(
        title: const Text('فیلتر اپ‌ها'),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Card(
              color: TikNetColors.surfaceVariant,
              child: SwitchListTile(
                title: const Text('فیلتر اپ (Split Tunnel)'),
                subtitle: Text(
                  perAppEnabled
                      ? 'فقط اپ‌های روشن‌شده از VPN استفاده می‌کنند.'
                      : 'خاموش = همه اپ‌ها از VPN استفاده می‌کنند.',
                  style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                ),
                value: perAppEnabled,
                activeColor: TikNetColors.primary,
                onChanged: (on) async {
                  await ref
                      .read(Preferences.perAppProxyMode.notifier)
                      .update(on ? PerAppProxyMode.include : PerAppProxyMode.off);
                },
              ),
            ),
          ),
          if (!appsLoading) ...[
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
            if (perAppEnabled && pinnedApps.isNotEmpty)
              _TikNetPinnedAppsBar(
                apps: pinnedApps,
                onTap: (pkg) {
                  ref.read(PerAppProxyProvider(mode).notifier).updatePkg(pkg.packageName);
                  sortTick.value++;
                },
              ),
          ],
          Expanded(
            child: _buildBody(
              context,
              ref,
              theme,
              asyncApps: asyncApps,
              selectedApps: selectedApps,
              displayList: displayList,
              searchQuery: searchQuery.value,
              mode: mode,
              perAppEnabled: perAppEnabled,
              onToggle: () => sortTick.value++,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme, {
    required AsyncSnapshot<Set<AppPackageInfo>> asyncApps,
    required AsyncValue<Map<String, int>> selectedApps,
    required List<AppPackageInfo> displayList,
    required String searchQuery,
    required AppProxyMode? mode,
    required bool perAppEnabled,
    required VoidCallback onToggle,
  }) {
    if (asyncApps.connectionState == ConnectionState.waiting || !asyncApps.hasData) {
      return const TikNetPerAppProxyLoadingView();
    }
    if (asyncApps.hasError) {
      return TikNetEmptyHint(
        icon: Icons.error_outline_rounded,
        title: 'خطا در بارگذاری',
        subtitle: 'لیست اپ‌های نصب‌شده خوانده نشد. یک‌بار از برنامه خارج و دوباره وارد شوید.',
      );
    }

    if (selectedApps.hasError) {
      return TikNetEmptyHint(
        icon: Icons.warning_amber_rounded,
        title: 'خطا در تنظیمات فیلتر',
        subtitle: 'لیست انتخاب‌ها بارگذاری نشد.',
      );
    }

    if (displayList.isEmpty) {
      return TikNetEmptyHint(
        icon: Icons.search_off_rounded,
        title: searchQuery.trim().isEmpty ? 'اپی یافت نشد' : 'نتیجه‌ای نیست',
        subtitle: searchQuery.trim().isEmpty
            ? 'اپ نصب‌شده‌ای روی گوشی شناسایی نشد.'
            : 'عبارت جستجو را عوض کنید.',
      );
    }

    final selectedMap = selectedApps.valueOrNull ?? const <String, int>{};
    final selectionLoading = selectedApps.isLoading;

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: displayList.length,
          itemBuilder: (context, index) {
            final app = displayList[index];
            final manualOn = perAppEnabled && PerAppProxyPage.isManuallyEnabled(selectedMap, app.packageName);
            final isOn = _isSwitchOn(selectedMap, app.packageName);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: manualOn ? TikNetColors.primary.withValues(alpha: 0.08) : TikNetColors.surface,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: app.icon == null
                    ? CircleAvatar(
                        backgroundColor: TikNetColors.surfaceVariant,
                        child: Icon(Icons.android_rounded, color: TikNetColors.onSurfaceVariant),
                      )
                    : CircleAvatar(backgroundImage: MemoryImage(app.icon!), radius: 24),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.name,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (manualOn) ...[
                      const Gap(6),
                      Icon(Icons.push_pin_rounded, size: 16, color: TikNetColors.primary),
                    ],
                  ],
                ),
                trailing: Switch.adaptive(
                  value: isOn,
                  onChanged: selectionLoading
                      ? null
                      : (_) {
                          ref.read(PerAppProxyProvider(mode).notifier).updatePkg(app.packageName);
                          onToggle();
                        },
                  activeColor: TikNetColors.primary,
                ),
              ),
            );
          },
        ),
        if (selectionLoading)
          Positioned(
            top: 8,
            left: 20,
            right: 20,
            child: Material(
              color: TikNetColors.surface,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Text(
                        'در حال آماده‌سازی انتخاب‌های قبلی…',
                        style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TikNetPinnedAppsBar extends StatelessWidget {
  const _TikNetPinnedAppsBar({required this.apps, required this.onTap});

  final List<AppPackageInfo> apps;
  final void Function(AppPackageInfo pkg) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 18, color: TikNetColors.connected),
              const Gap(8),
              Text(
                'اپ‌های روشن‌شده (${toPersianDigits('${apps.length}')})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Gap(8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: apps.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (context, index) {
                final app = apps[index];
                return Material(
                  color: TikNetColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => onTap(app),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 128,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TikNetColors.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          if (app.icon != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(app.icon!, width: 36, height: 36, cacheWidth: 36, cacheHeight: 36),
                            )
                          else
                            const Icon(Icons.android_rounded, size: 36),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              app.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
