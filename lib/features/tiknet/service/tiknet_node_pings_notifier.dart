import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// On-demand real proxy latency via sing-box urltest (same path that works after connect).
/// If VPN is off, starts connection first — HTTP-to-host probes are unreliable for VLESS/etc.
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

    final service = ref.read(tikNetClientPingServiceProvider);

    try {
      final ready = await _ensureConnectedForUrlTest();
      if (!ready) return const {};

      return await service.measureNodePingsFromCore(catalog).timeout(const Duration(seconds: 14));
    } on TimeoutException {
      return const {};
    }
  }

  /// Urltest needs a running core; connect if needed and wait briefly.
  Future<bool> _ensureConnectedForUrlTest() async {
    if (ref.read(connectionNotifierProvider).valueOrNull is Connected) return true;

    try {
      await ref.read(syncServiceProvider).applyProfileFromCache();
    } catch (_) {}

    await ref.read(Preferences.startedByUser.notifier).update(true);

    final status = ref.read(connectionNotifierProvider).valueOrNull;
    if (status is! Connected && status is! Connecting) {
      try {
        await ref.read(connectionNotifierProvider.notifier).toggleConnection();
      } catch (_) {
        return false;
      }
    }

    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final s = ref.read(connectionNotifierProvider).valueOrNull;
      if (s is Connected) return true;
      if (s is Disconnected && i > 4) {
        // Connect failed / aborted — stop waiting.
        if (i > 8) return false;
      }
    }
    return ref.read(connectionNotifierProvider).valueOrNull is Connected;
  }
}

final tikNetNodePingsProvider =
    AutoDisposeAsyncNotifierProvider<TikNetNodePingsNotifier, Map<String, TikNetClientPingResult>>(
  TikNetNodePingsNotifier.new,
);
