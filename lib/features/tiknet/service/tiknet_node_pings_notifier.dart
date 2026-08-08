import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// On-demand pings — never toggles the user-facing VPN / startedByUser.
/// - VPN on (user): sing-box urltest through the live core (stock Hiddify style).
/// - VPN off: TCP estimate only — no temporary proxy probe (that raced Connect).
/// Call [measure] only from explicit UI (e.g. server picker refresh).
class TikNetNodePingsNotifier extends AutoDisposeAsyncNotifier<Map<String, TikNetClientPingResult>> {
  @override
  Future<Map<String, TikNetClientPingResult>> build() async => const {};

  bool get isMeasuring => state.isLoading;

  Future<void> measure() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_runMeasure);
  }

  void clear() => state = const AsyncData({});

  Future<Map<String, TikNetClientPingResult>> _runMeasure() async {
    // If the user picked a catalog server that is not merged yet, inject it first
    // so urltest can actually see the outbound.
    try {
      final sync = ref.read(syncServiceProvider);
      final sel = sync.selectedServer;
      if (selectionUsesCatalog(sel)) {
        await sync.ensureCatalogServerInProfile(
          sel.catalogId ?? catalogIdFromOutboundTag(sel.personalTag),
        );
        ref.invalidate(personalOutboundProvider);
      }
    } catch (_) {}

    final catalog = await ref
        .read(personalOutboundProvider.future)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => const TikNetPersonalNodesState(catalog: null, nodePings: {}),
        )
        .then((s) => s.catalog);
    if (catalog == null || catalog.nodes.isEmpty) return const {};

    final startedByUser = ref.read(Preferences.startedByUser);
    final connected = ref.read(connectionNotifierProvider).valueOrNull is Connected;
    final service = ref.read(tikNetClientPingServiceProvider);

    // Stock Hiddify: urltest only against a live core. Starting a temporary
    // proxy-mode probe raced Connect, stuck ServiceMode on proxy, and aborted
    // real tunnels — so when VPN is off we only do a cheap TCP estimate.
    if (startedByUser && connected) {
      return await service.measureNodePingsFromCore(catalog).timeout(const Duration(seconds: 50));
    }
    if (startedByUser && !connected) {
      throw StateError('vpn connecting — skip ping probe');
    }
    return await service.measureNodePingsTcp(catalog).timeout(const Duration(seconds: 20));
  }
}

final tikNetNodePingsProvider =
    AutoDisposeAsyncNotifierProvider<TikNetNodePingsNotifier, Map<String, TikNetClientPingResult>>(
  TikNetNodePingsNotifier.new,
);
