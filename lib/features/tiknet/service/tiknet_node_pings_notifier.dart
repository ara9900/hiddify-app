import 'dart:async';

import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// On-demand pings (never auto-runs on list load — avoids ANR).
/// Connected: sing-box HTTP urltest (real proxy latency).
/// Disconnected: HTTP HEAD/GET to each outbound probe URL.
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

    final connected = ref.read(connectionNotifierProvider).valueOrNull is Connected;
    final service = ref.read(tikNetClientPingServiceProvider);

    try {
      if (connected) {
        final fromCore = await service.measureNodePingsFromCore(catalog).timeout(const Duration(seconds: 12));
        if (fromCore.isNotEmpty) return fromCore;
      }
      return await service.measureNodePingsHttp(catalog).timeout(const Duration(seconds: 14));
    } on TimeoutException {
      return const {};
    }
  }
}

final tikNetNodePingsProvider =
    AutoDisposeAsyncNotifierProvider<TikNetNodePingsNotifier, Map<String, TikNetClientPingResult>>(
  TikNetNodePingsNotifier.new,
);
