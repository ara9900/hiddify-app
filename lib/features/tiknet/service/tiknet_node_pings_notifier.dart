import 'dart:async';

import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// On-demand HTTP urltest pings (never auto-runs on list load — avoids ANR).
class TikNetNodePingsNotifier extends AutoDisposeAsyncNotifier<Map<String, TikNetClientPingResult>> {
  @override
  Future<Map<String, TikNetClientPingResult>> build() async => const {};

  bool get isMeasuring => state.isLoading;

  Future<void> measure() async {
    if (state.isLoading) return;
    final connected = ref.read(connectionNotifierProvider).valueOrNull is Connected;
    if (!connected) {
      state = const AsyncData({});
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(_runMeasure);
  }

  void clear() => state = const AsyncData({});

  Future<Map<String, TikNetClientPingResult>> _runMeasure() async {
    final catalog = ref.read(personalOutboundProvider).valueOrNull?.catalog;
    if (catalog == null || catalog.nodes.isEmpty) return const {};
    try {
      return await ref
          .read(tikNetClientPingServiceProvider)
          .measureNodePingsFromCore(catalog)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      return const {};
    }
  }
}

final tikNetNodePingsProvider =
    AutoDisposeAsyncNotifierProvider<TikNetNodePingsNotifier, Map<String, TikNetClientPingResult>>(
  TikNetNodePingsNotifier.new,
);
