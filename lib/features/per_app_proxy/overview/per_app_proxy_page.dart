import 'package:dartx/dartx.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/per_app_proxy/model/app_package_info.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_loading_notifier.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/tiknet/widgets/tiknet_loading_view.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';

class PerAppProxyPage extends HookConsumerWidget with PresLogger {
  const PerAppProxyPage({super.key});

  /// Apps the user explicitly turned on stay at the top of the list.
  static bool isManuallyEnabled(Map<String, int> selected, String packageName) {
    final flag = selected[packageName];
    if (flag == null) return false;
    return PkgFlag.userSelection.check(flag) && PkgFlag.checkboxValue(flag) == true;
  }

  int _getPriority(AppPackageInfo app, Map<String, int> selected) {
    final flag = selected[app.packageName];
    if (flag == null) return 5;
    if (PkgFlag.userSelection.check(flag) && PkgFlag.checkboxValue(flag) == true) return 0;
    if (PkgFlag.userSelection.check(flag)) return 1;
    if (PkgFlag.autoSelection.check(flag) && !PkgFlag.forceDeselection.check(flag)) return 2;
    if (PkgFlag.forceDeselection.check(flag)) return 3;
    return 4;
  }

  Future<Set<AppPackageInfo>> getApps(bool hideSystem) async {
    if (!PlatformUtils.isAndroid) return {};
    return (await InstalledApps.getInstalledApps(
      hideSystem,
      true,
    )).map((e) => AppPackageInfo(packageName: e.packageName, name: e.name, icon: e.icon)).toSet();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final localizations = MaterialLocalizations.of(context);

    final mode = ref.watch(Preferences.perAppProxyMode).toAppProxy();
    final selectedApps = ref.watch(PerAppProxyProvider(mode));

    final hideSystemApps = useState(false);
    final isSearching = useState(false);
    final searchQuery = useState("");
    final sortListener = useState(false);

    final asyncApps = useFuture(useMemoized(() => getApps(false)));
    final asyncAppsHideSys = useFuture(useMemoized(() => getApps(true)));

    final asyncFilteredApps = hideSystemApps.value ? asyncAppsHideSys : asyncApps;

    final displayedApps = useMemoized<AsyncValue<List<AppPackageInfo>>>(
      () {
        if (!(selectedApps.hasValue &&
            selectedApps is AsyncData &&
            asyncFilteredApps.hasData &&
            asyncFilteredApps.connectionState == ConnectionState.done))
          return const AsyncValue.loading();
        final appsList = asyncFilteredApps.requireData.toList();
        if (searchQuery.value.isBlank) {
          appsList.sort((a, b) {
            final priorityA = _getPriority(a, selectedApps.requireValue);
            final priorityB = _getPriority(b, selectedApps.requireValue);
            return priorityA.compareTo(priorityB);
          });
          return AsyncValue.data(appsList);
        }
        final filteredAppsList = appsList
            .filter((e) => e.name.toLowerCase().contains(searchQuery.value.toLowerCase()))
            .toList();
        return AsyncValue.data(filteredAppsList);
      },
      [
        asyncFilteredApps.connectionState == ConnectionState.done,
        hideSystemApps.value,
        selectedApps.hasValue,
        searchQuery.value,
        sortListener.value,
      ],
    );

    if (mode != null) {
      ref.listen(PerAppProxyProvider(mode), (previous, next) {
        if (previous != null) {
          if ((previous, next) case (AsyncData(value: final prevData), AsyncData(value: final nextData))) {
            if (nextData.isNotEmpty) {
              if ((nextData.length - prevData.length).abs() > 1) sortListener.value = !sortListener.value;
            }
          }
        }
      });
    }

    final scrollController = useScrollController();
    const double scrollThreshold = 300.0;
    final showScrollToTop = useState<bool>(false);
    useEffect(() {
      void listener() {
        showScrollToTop.value = scrollController.offset > scrollThreshold;
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, []);
    useEffect(() {
      showScrollToTop.value = false;
      return null;
    }, [displayedApps]);

    return Scaffold(
      appBar: isSearching.value
          ? AppBar(
              title: TextFormField(
                onChanged: (value) => searchQuery.value = value,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "${localizations.searchFieldLabel}...",
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              leading: IconButton(
                onPressed: () {
                  searchQuery.value = "";
                  isSearching.value = false;
                },
                icon: const Icon(Icons.close),
                tooltip: localizations.cancelButtonLabel,
              ),
            )
          : AppBar(
              title: Text(t.pages.settings.routing.perAppProxy.title),
              actions: [
                IconButton(
                  icon: const Icon(FluentIcons.search_24_regular),
                  onPressed: () => isSearching.value = true,
                  tooltip: localizations.searchFieldLabel,
                ),
                MenuAnchor(
                  menuChildren: <Widget>[
                    SubmenuButton(
                      menuChildren: <Widget>[
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.perAppProxy.options.import.clipboard),
                          onPressed: () async => await ref
                              .read(dialogNotifierProvider.notifier)
                              .showConfirmation(
                                title: t.common.msg.import.confirm,
                                message: t.dialogs.confirmation.perAppProxy.import.msg,
                              )
                              .then((shouldImport) async {
                                if (shouldImport) await ref.read(PerAppProxyProvider(mode).notifier).importClipboard();
                              }),
                        ),
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.perAppProxy.options.import.file),
                          onPressed: () async => await ref
                              .read(dialogNotifierProvider.notifier)
                              .showConfirmation(
                                title: t.pages.settings.routing.perAppProxy.options.import.file,
                                message: t.pages.settings.routing.perAppProxy.options.import.msg,
                              )
                              .then((shouldImport) async {
                                if (shouldImport) await ref.read(PerAppProxyProvider(mode).notifier).importFile();
                              }),
                        ),
                      ],
                      child: Text(t.common.import),
                    ),
                    SubmenuButton(
                      menuChildren: <Widget>[
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.perAppProxy.options.export.clipboard),
                          onPressed: () async => await ref.read(PerAppProxyProvider(mode).notifier).exportClipboard(),
                        ),
                        MenuItemButton(
                          child: Text(t.pages.settings.routing.perAppProxy.options.export.file),
                          onPressed: () async => await ref.read(PerAppProxyProvider(mode).notifier).exportFile(),
                        ),
                      ],
                      child: Text(t.common.export),
                    ),
                    if (ref.watch(ConfigOptions.region) != Region.other)
                      MenuItemButton(
                        child: Text(t.pages.settings.routing.perAppProxy.options.shareToAll),
                        onPressed: () async => await ref
                            .read(appProxyLoadingProvider.notifier)
                            .doAsync(ref.read(PerAppProxyProvider(mode).notifier).shareOnGithub),
                      ),
                    const PopupMenuDivider(),
                    MenuItemButton(
                      child: Text(t.pages.settings.routing.perAppProxy.options.clearAllSelections),
                      onPressed: () => ref.read(PerAppProxyProvider(mode).notifier).clearAll(),
                    ),
                  ],
                  builder: (context, controller, child) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: ref.watch(appProxyLoadingProvider)
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator()),
                          )
                        : IconButton(
                            onPressed: () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                controller.open();
                              }
                            },
                            icon: const Icon(Icons.more_vert_rounded),
                          ),
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      PopupMenuButton(
                        borderRadius: BorderRadius.circular(8),
                        position: PopupMenuPosition.under,
                        tooltip: (mode?.toPerAppProxy() ?? PerAppProxyMode.off).present(t).message,
                        initialValue: mode?.toPerAppProxy() ?? PerAppProxyMode.off,
                        onSelected: (e) async {
                          if (ref.read(Preferences.autoAppsSelectionRegion) != null)
                            await ref.read(PerAppProxyProvider(mode).notifier).clearAutoSelected();
                          if (e == PerAppProxyMode.off && context.mounted) context.pop();
                          await ref.read(Preferences.perAppProxyMode.notifier).update(e);
                        },
                        itemBuilder: (context) => PerAppProxyMode.values
                            .map((e) => PopupMenuItem(value: e, child: Text(e.present(t).message)))
                            .toList(),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surface,
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              const Gap(16),
                              Text(mode?.present(t).title ?? ''),
                              const Gap(4),
                              Icon(Icons.arrow_drop_down_rounded, color: theme.colorScheme.onSurfaceVariant),
                              const Gap(8),
                            ],
                          ),
                        ),
                      ),
                      const Gap(8),
                      ChoiceChip(
                        label: Text(t.pages.settings.routing.perAppProxy.hideSysApps),
                        selected: hideSystemApps.value,
                        onSelected: (value) => hideSystemApps.value = value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: showScrollToTop.value
          ? FloatingActionButton(
              onPressed: () =>
                  scrollController.animateTo(0.0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut),
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            )
          : (ref.watch(ConfigOptions.region) != Region.other)
          ? FloatingActionButton.extended(
              onPressed: () async =>
                  await ref.read(bottomSheetsNotifierProvider.notifier).showAutoAppsSelection(mode: mode!),
              label: Text(t.pages.settings.routing.perAppProxy.autoSelection.title),
              icon: Icon(
                ref.watch(Preferences.autoAppsSelectionRegion) == null
                    ? Icons.toggle_off_outlined
                    : Icons.toggle_on_rounded,
              ),
            )
          : null,
      body: displayedApps.when(
        data: (packages) {
          final selectedMap = selectedApps.requireValue;
          final pinned = mode != null
              ? packages.where((p) => isManuallyEnabled(selectedMap, p.packageName)).toList()
              : <AppPackageInfo>[];
          return CustomScrollView(
            controller: scrollController,
            slivers: [
              if (tikNetMode && mode != null && pinned.isNotEmpty)
                SliverToBoxAdapter(
                  child: _PinnedAppsSection(
                    apps: pinned,
                    onTap: (pkg) => ref.read(PerAppProxyProvider(mode).notifier).updatePkg(pkg.packageName),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 88),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final package = packages[index];
                      final flag = selectedMap[package.packageName];
                      final manualOn = isManuallyEnabled(selectedMap, package.packageName);
                      return CheckboxListTile.adaptive(
                        tileColor: manualOn ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
                        title: Row(
                          children: [
                            Flexible(child: Text(package.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (manualOn) ...[
                              const Gap(6),
                              Icon(Icons.push_pin_rounded, size: 16, color: theme.colorScheme.primary),
                            ],
                            if (flag != null && PkgFlag.forceDeselection.check(flag)) ...[
                              const Gap(6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          package.packageName,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: flag == null ? false : PkgFlag.checkboxValue(flag),
                        tristate: true,
                        onChanged: (_) {
                          ref.read(PerAppProxyProvider(mode).notifier).updatePkg(package.packageName);
                          sortListener.value = !sortListener.value;
                        },
                        secondary: package.icon == null
                            ? null
                            : Image.memory(package.icon!, width: 48, height: 48, cacheWidth: 48, cacheHeight: 48),
                      );
                    },
                    childCount: packages.length,
                  ),
                ),
              ),
            ],
          );
        },
        error: (error, _) => SliverErrorBodyPlaceholder(error.toString()),
        loading: () => tikNetMode ? const TikNetPerAppProxyLoadingView() : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _PinnedAppsSection extends StatelessWidget {
  const _PinnedAppsSection({required this.apps, required this.onTap});

  final List<AppPackageInfo> apps;
  final void Function(AppPackageInfo pkg) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
          const Gap(10),
          SizedBox(
            height: 76,
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
                      width: 132,
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
                              child: Image.memory(app.icon!, width: 40, height: 40, cacheWidth: 40, cacheHeight: 40),
                            )
                          else
                            const Icon(Icons.android_rounded, size: 40),
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
          const Gap(8),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
        ],
      ),
    );
  }
}
