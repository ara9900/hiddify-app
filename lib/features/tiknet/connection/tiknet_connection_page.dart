import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/tiknet/service/announcement_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_user_info_provider.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';

class TikNetConnectionPage extends HookConsumerWidget {
  const TikNetConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final stats = ref.watch(statsNotifierProvider).asData?.value;
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull ?? false;

    final subscriptionExpired = () {
      final info = ref.watch(tikNetUserInfoProvider).valueOrNull;
      final exp = info?.expireDate;
      return exp != null && DateTime.now().isAfter(exp);
    }();
    final subscriptionExpiredDate = ref.watch(tikNetUserInfoProvider).valueOrNull?.expireDate;

    final statusLabel = switch (connectionStatus) {
      AsyncData(value: Connected()) when requiresReconnect => 'بروزرسانی اتصال',
      AsyncData(value: Connected()) => 'متصل',
      AsyncData(value: Connecting()) => 'در حال اتصال',
      AsyncData(value: Disconnecting()) => 'در حال قطع',
      AsyncData(value: Disconnected()) => 'قطع',
      _ => 'قطع',
    };
    final statusColor = switch (connectionStatus) {
      AsyncData(value: Connected()) => TikNetColors.connected,
      AsyncData(value: Connecting()) || AsyncData(value: Disconnecting()) => TikNetColors.connecting,
      _ => TikNetColors.disconnected,
    };

    final enabled = switch (connectionStatus) {
      AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
      _ => false,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('TikNet'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (subscriptionExpired && subscriptionExpiredDate != null) ...[
                    Card(
                      color: TikNetColors.error.withValues(alpha: 0.15),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: TikNetColors.error, size: 24),
                            const Gap(12),
                            Expanded(
                              child: Text(
                                'اشتراک شما در تاریخ ${formatShamsiDate(subscriptionExpiredDate)} به پایان رسیده',
                                style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onBackground),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Gap(16),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                if (connectionStatus case AsyncData(value: Connecting() || Disconnecting()))
                                  BoxShadow(color: statusColor.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2),
                              ],
                            ),
                          ),
                          const Gap(12),
                          Text(
                            statusLabel,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(32),
                  Center(
                    child: AbsorbPointer(
                      absorbing: subscriptionExpired,
                      child: _TikNetConnectButton(
                        connectionStatus: connectionStatus,
                        requiresReconnect: requiresReconnect,
                        enabled: enabled && !subscriptionExpired,
                        onTap: () async {
                          if (ref.read(activeProfileProvider).valueOrNull == null) {
                            await ref.read(dialogNotifierProvider.notifier).showNoActiveProfile();
                            ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
                            return;
                          }
                          if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
                            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
                          }
                        },
                      ),
                    ),
                  ),
                  const Gap(24),
                  const _AnnouncementBox(),
                  const Gap(24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(
                            icon: Icons.dns_rounded,
                            label: 'سرور فعلی',
                            value: switch (activeProxy) {
                              AsyncData(value: final p) => p.tagDisplay,
                              _ => '—',
                            },
                          ),
                          const Divider(height: 24, color: TikNetColors.border),
                          _InfoRow(
                            icon: Icons.schedule_rounded,
                            label: 'مدت اتصال',
                            value: '—',
                          ),
                          const Divider(height: 24, color: TikNetColors.border),
                          _InfoRow(
                            icon: Icons.arrow_upward_rounded,
                            label: 'سرعت آپلود',
                            value: stats != null ? toPersianDigits(stats.uplink.toInt().speed()) : '—',
                          ),
                          const Divider(height: 24, color: TikNetColors.border),
                          _InfoRow(
                            icon: Icons.arrow_downward_rounded,
                            label: 'سرعت دانلود',
                            value: stats != null ? toPersianDigits(stats.downlink.toInt().speed()) : '—',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
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
    final isConnected = switch (connectionStatus) {
      AsyncData(value: Connected()) => true,
      _ => false,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(80),
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? TikNetColors.connected : TikNetColors.primary,
            boxShadow: [
              BoxShadow(
                color: (isConnected ? TikNetColors.connected : TikNetColors.primary).withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              isConnected ? Icons.power_settings_new_rounded : Icons.shield_rounded,
              size: 64,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: TikNetColors.onSurfaceVariant),
        const Gap(12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.left,
          ),
        ),
      ],
    );
  }
}

class _AnnouncementBox extends ConsumerWidget {
  const _AnnouncementBox();

  static Color _colorForType(String type) {
    return switch (type.toLowerCase()) {
      'warning' => const Color(0xFFEAB308),
      'error' => TikNetColors.error,
      'success' => TikNetColors.connected,
      _ => TikNetColors.primary,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementProvider);
    return async.when(
      data: (AnnouncementMessage? message) {
        if (message == null || !message.show || message.text.isEmpty) return const SizedBox.shrink();
        final color = _colorForType(message.type);
        return Card(
          color: color.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: color, size: 22),
                const Gap(12),
                Expanded(
                  child: Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: TikNetColors.onBackground),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
