import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Latency via sing-box urltest (same as Hiddify proxy list). Requires VPN core running.
class TikNetClientPingService {
  TikNetClientPingService(this._ref);

  final Ref _ref;

  /// Panel catalog entries are not sing-box outbounds — skip HTTP/TCP probes.
  TikNetServerCatalog catalogWithoutClientPing(TikNetServerCatalog catalog) {
    final servers = catalog.servers
        .map(
          (s) => s.copyWithClientPing(state: TikNetClientPingState.noTarget),
        )
        .toList();
    return TikNetServerCatalog(
      personalAvailable: catalog.personalAvailable,
      servers: servers,
      personalPing: null,
      displayMode: catalog.displayMode,
    );
  }

  /// urltest on [groupTag] then read [OutboundInfo.urlTestDelay] per node tag.
  Future<Map<String, TikNetClientPingResult>> measureNodePingsFromCore(
    TikNetPersonalOutboundCatalog catalog,
  ) async {
    final nodes = catalog.nodes;
    if (nodes.isEmpty) return const {};

    final running = await _ref.read(serviceRunningProvider.future).catchError((_) => false);
    if (!running) return const {};

    final groupTag = catalog.mainGroupTag.trim();
    if (groupTag.isEmpty) return const {};

    try {
      await _ref
          .read(proxyRepositoryProvider)
          .urlTest(groupTag)
          .getOrElse((_) => unit)
          .run()
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      return const {};
    } catch (_) {
      return const {};
    }

    OutboundGroup? group;
    try {
      group = await _ref
          .read(proxyRepositoryProvider)
          .watchProxies()
          .map((e) => e.fold((_) => null, (g) => g))
          .where((g) => g != null)
          .map((g) => g!)
          .first
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return const {};
    } catch (_) {
      return const {};
    }

    return _delaysFromGroup(group, nodes);
  }

  Map<String, TikNetClientPingResult> _delaysFromGroup(
    OutboundGroup? group,
    List<TikNetPersonalProxyNode> nodes,
  ) {
    if (group == null) return const {};

    final delayByTag = <String, int>{
      for (final item in group.items)
        if (item.tag.isNotEmpty) item.tag: item.urlTestDelay,
    };

    final out = <String, TikNetClientPingResult>{};
    for (final node in nodes) {
      final delay = delayByTag[node.tag];
      if (delay == null) {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
        continue;
      }
      if (delay <= 0 || delay >= 65000) {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
        continue;
      }
      out[node.tag] = TikNetClientPingResult(
        state: TikNetClientPingState.reachable,
        pingMs: delay,
      );
    }
    return out;
  }
}

final tikNetClientPingServiceProvider = Provider<TikNetClientPingService>(
  (ref) => TikNetClientPingService(ref),
);
