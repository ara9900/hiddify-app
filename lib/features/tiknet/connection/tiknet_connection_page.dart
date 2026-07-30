import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/tiknet/connection/tiknet_server_picker.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/announcement_service.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/server_catalog_provider.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_node_pings_notifier.dart';
import 'package:hiddify/features/tiknet/service/tiknet_outbound_apply.dart';
import 'package:hiddify/features/tiknet/service/tiknet_smart_connect.dart';
import 'package:hiddify/features/tiknet/service/tiknet_telemetry_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_user_info_provider.dart';
import 'package:hiddify/features/tiknet/widgets/tiknet_app_version_label.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetConnectionPage extends HookConsumerWidget {
  const TikNetConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull ?? false;

    final selected = ref.watch(selectedServerProvider);
    final catalog = ref.watch(serverCatalogProvider).valueOrNull;
    final personalNodes = ref.watch(personalOutboundProvider).valueOrNull;
    final nodePings = ref.watch(tikNetNodePingsProvider).valueOrNull;
    final smartLocked = ref.watch(Preferences.tikNetSmartLockedTag);
    final smartPicking = ref.watch(tikNetSmartPickingProvider);
    final serverInfo = resolveSelectedServerInfo(
      selected: selected,
      catalog: catalog,
      personalCatalog: personalNodes?.catalog,
      personalNodePings: nodePings,
      smartLockedTag: smartLocked,
    );

    final entitlement = ref.watch(tikNetEntitlementProvider);
    final vpnBlocked = !entitlement.allowed;

    useEffect(() {
      if (vpnBlocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(ref.read(connectionNotifierProvider.notifier).forceStopForEntitlementBlock());
        });
      }
      return null;
    }, [vpnBlocked, entitlement.block]);

    final isConnected = connectionStatus.valueOrNull is Connected;
    final isConnecting = connectionStatus.valueOrNull is Connecting;
    final isDisconnecting = connectionStatus.valueOrNull is Disconnecting;

    final statusLabel = switch (connectionStatus) {
      AsyncData(value: Connected()) when smartPicking => 'انتخاب بهترین سرور…',
      AsyncData(value: Connected()) when requiresReconnect => 'نیاز به بروزرسانی',
      AsyncData(value: Connected()) => 'متصل به اینترنت',
      AsyncData(value: Connecting()) => 'در حال اتصال…',
      AsyncData(value: Disconnecting()) => 'در حال قطع…',
      _ => 'قطع شده',
    };
    final statusColor = switch (connectionStatus) {
      AsyncData(value: Connected()) when smartPicking => TikNetColors.connecting,
      AsyncData(value: Connected()) => TikNetColors.connected,
      AsyncData(value: Connecting()) || AsyncData(value: Disconnecting()) => TikNetColors.connecting,
      _ => TikNetColors.disconnected,
    };
    final statusHint = switch (connectionStatus) {
      AsyncData(value: Connected()) when smartPicking => 'پینگ سرورها در حال اندازه‌گیری است',
      AsyncData(value: Connected()) => 'ترافیک شما از طریق VPN عبور می‌کند',
      AsyncData(value: Connecting()) => 'لطفاً چند ثانیه صبر کنید',
      AsyncData(value: Disconnecting()) => 'در حال قطع اتصال',
      _ => 'برای اتصال، دکمه پایین را بزنید',
    };

    ref.listen(connectionNotifierProvider, (prev, next) {
      final wasConnected = prev?.valueOrNull is Connected;
      final isConnectedNow = next.valueOrNull is Connected;
      if (next case AsyncData(value: Connected()) when !wasConnected) {
        ref.read(tikNetTelemetryServiceProvider).send('connect_success');
        unawaited(applyTikNetPersonalOutboundSelection(ref));
      } else if (wasConnected && !isConnectedNow) {
        unawaited(clearTikNetSmartLockWidget(ref));
        ref.read(tikNetSmartPickingProvider.notifier).state = false;
      } else if (next case AsyncError(:final error) when prev is! AsyncError) {
        ref.read(tikNetTelemetryServiceProvider).send(
          'connect_fail',
          payload: {'error': error.toString()},
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('اتصال امن'),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(left: 16),
            child: Center(child: TikNetAppVersionLabel(compact: true)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(serverCatalogProvider);
            ref.invalidate(personalOutboundProvider);
            await ref.read(syncServiceProvider).syncAll();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (vpnBlocked && entitlement.message.isNotEmpty) ...[
                        _AlertBanner(
                          icon: Icons.warning_amber_rounded,
                          color: TikNetColors.error,
                          text: entitlement.message,
                        ),
                        const Gap(16),
                      ],
                      _ConnectionStatusHero(
                        statusLabel: statusLabel,
                        statusHint: statusHint,
                        statusColor: statusColor,
                        isConnected: isConnected,
                        isBusy: isConnecting || isDisconnecting,
                        serverTitle: serverInfo.title,
                      ),
                      const Gap(16),
                      const TikNetServerSelectorCard(),
                      const Gap(16),
                      const _AnnouncementBox(),
                      const Gap(28),
                      Center(
                        child: AbsorbPointer(
                          absorbing: vpnBlocked && !isConnected && !isConnecting && !isDisconnecting,
                          child: _TikNetConnectButton(
                            connectionStatus: connectionStatus,
                            requiresReconnect: requiresReconnect,
                            enabled: (!vpnBlocked || isConnected || isConnecting || isDisconnecting),
                            onTap: () async {
                              if (isConnecting || isDisconnecting) {
                                await ref.read(connectionNotifierProvider.notifier).abortConnection();
                                return;
                              }
                              if (vpnBlocked) {
                                if (isConnected) {
                                  await ref.read(connectionNotifierProvider.notifier).abortConnection();
                                }
                                return;
                              }
                              if (requiresReconnect == true &&
                                  ref.read(connectionNotifierProvider).valueOrNull is Connected) {
                                await ref.read(connectionNotifierProvider.notifier).reconnect(
                                  ref.read(activeProfileProvider).valueOrNull,
                                );
                                return;
                              }
                              if (ref.read(activeProfileProvider).valueOrNull == null) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('در حال دریافت سرور از پنل…'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                final sync = ref.read(syncServiceProvider);
                                try {
                                  final ok = await sync.syncAllAndApplyProfile().timeout(
                                    const Duration(seconds: 25),
                                    onTimeout: () => false,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  if (!ok || ref.read(activeProfileProvider).valueOrNull == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('سرور آماده نیست. از حساب من → بروزرسانی تلاش کنید.'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }
                                } on SyncTokenExpiredException {
                                  if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  return;
                                }
                              }
                              await ref.read(connectionNotifierProvider.notifier).toggleConnection();
                            },
                          ),
                        ),
                      ),
                      const Gap(8),
                      Center(
                        child: Text(
                          isConnecting || isDisconnecting
                              ? 'برای لغو، دوباره دکمه را بزنید'
                              : isConnected
                                  ? 'برای قطع اتصال بزنید'
                                  : 'برای اتصال به سرور انتخابی بزنید',
                          style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionStatusHero extends StatelessWidget {
  const _ConnectionStatusHero({
    required this.statusLabel,
    required this.statusHint,
    required this.statusColor,
    required this.isConnected,
    required this.isBusy,
    required this.serverTitle,
  });

  final String statusLabel;
  final String statusHint;
  final Color statusColor;
  final bool isConnected;
  final bool isBusy;
  final String serverTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            statusColor.withValues(alpha: 0.18),
            TikNetColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: isConnected ? 0.5 : 0.25), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withValues(alpha: 0.2),
            ),
            child: Icon(
              isConnected ? Icons.verified_user_rounded : (isBusy ? Icons.sync_rounded : Icons.shield_outlined),
              color: statusColor,
              size: 30,
            ),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const Gap(4),
                Text(statusHint, style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant)),
                const Gap(6),
                Text(
                  'مقصد: $serverTitle',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const Gap(12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _TikNetConnectButton extends StatelessWidget {
  const _TikNetConnectButton({
    required this.connectionStatus,
    required this.requiresReconnect,
    required this.enabled,
    required this.onTap,
  });

  final AsyncValue<ConnectionStatus> connectionStatus;
  final bool requiresReconnect;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isConnected = connectionStatus.valueOrNull is Connected;
    final isBusy = connectionStatus.valueOrNull is Connecting || connectionStatus.valueOrNull is Disconnecting;
    final color = isConnected ? TikNetColors.connected : TikNetColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(80),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 168,
          height: 168,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? color : color.withValues(alpha: 0.4),
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 0,
                ),
            ],
          ),
          child: Center(
            child: isBusy
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected ? Icons.power_settings_new_rounded : Icons.shield_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                      if (requiresReconnect && isConnected) ...[
                        const Gap(4),
                        const Text('بروزرسانی', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementBox extends ConsumerWidget {
  const _AnnouncementBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementProvider);
    return async.when(
      data: (AnnouncementMessage? message) {
        if (message == null || !message.show || message.text.isEmpty) return const SizedBox.shrink();
        final color = switch (message.type.toLowerCase()) {
          'warning' => const Color(0xFFEAB308),
          'error' => TikNetColors.error,
          'success' => TikNetColors.connected,
          _ => TikNetColors.primary,
        };
        return _AlertBanner(
          icon: Icons.campaign_outlined,
          color: color,
          text: message.text,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
