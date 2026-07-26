import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// On-demand pings — never toggles the user-facing VPN / startedByUser.
/// - VPN on (user): sing-box urltest through the live core.
/// - VPN off: temporary ServiceMode.proxy urltest probe, then disconnect.
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
    final catalog = ref.read(personalOutboundProvider).valueOrNull?.catalog;
    if (catalog == null || catalog.nodes.isEmpty) return const {};

    final startedByUser = ref.read(Preferences.startedByUser);
    final connected = ref.read(connectionNotifierProvider).valueOrNull is Connected;
    final service = ref.read(tikNetClientPingServiceProvider);
    final notifier = ref.read(connectionNotifierProvider.notifier);

    // Never start a proxy probe while the user intends VPN (Connecting / restore).
    // That used to leave ServiceMode stuck on proxy.
    if (startedByUser) {
      if (!connected) {
        throw StateError('vpn connecting — skip ping probe');
      }
      return await service.measureNodePingsFromCore(catalog).timeout(const Duration(seconds: 50));
    }
    // Pre-connect: real urltest via temporary proxy-mode core (not TCP).
    return await notifier
        .runUrlTestProbe(
          () => service.measureNodePingsFromCore(catalog, skipServiceCheck: true),
        )
        .timeout(const Duration(seconds: 75));
  }
}

final tikNetNodePingsProvider =
    AutoDisposeAsyncNotifierProvider<TikNetNodePingsNotifier, Map<String, TikNetClientPingResult>>(
  TikNetNodePingsNotifier.new,
);
