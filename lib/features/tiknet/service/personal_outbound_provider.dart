import 'dart:convert';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetPersonalNodesState {
  const TikNetPersonalNodesState({
    required this.catalog,
    required this.nodePings,
  });

  final TikNetPersonalOutboundCatalog? catalog;
  final Map<String, TikNetClientPingResult> nodePings;
}

final personalOutboundProvider = FutureProvider<TikNetPersonalNodesState>((ref) async {
  ref.watch(Preferences.tikNetCachedConfig);
  final rawB64 = ref.read(Preferences.tikNetCachedConfig);
  if (rawB64.isEmpty) {
    return const TikNetPersonalNodesState(catalog: null, nodePings: {});
  }
  try {
    final content = utf8.decode(base64Decode(rawB64));
    final catalog = parsePersonalOutboundsFromConfig(content);
    if (catalog == null || catalog.isEmpty) {
      return const TikNetPersonalNodesState(catalog: null, nodePings: {});
    }
    final ping = ref.read(tikNetClientPingServiceProvider);
    final pings = <String, TikNetClientPingResult>{};
    for (final node in catalog.nodes) {
      pings[node.tag] = await ping.measureUrl(node.probeUrl.isEmpty ? null : node.probeUrl);
    }
    return TikNetPersonalNodesState(catalog: catalog, nodePings: pings);
  } catch (_) {
    return const TikNetPersonalNodesState(catalog: null, nodePings: {});
  }
});
