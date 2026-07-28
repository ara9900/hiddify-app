import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_core_selection.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// True while smart-connect is measuring pings / selecting outbound.
final tikNetSmartPickingProvider = StateProvider<bool>((ref) => false);

Future<void> clearTikNetSmartLock(Ref ref) async {
  await ref.read(Preferences.tikNetSmartLockedTag.notifier).update('');
  await ref.read(Preferences.tikNetSmartLockedGroup.notifier).update('');
}

Future<void> clearTikNetSmartLockWidget(WidgetRef ref) async {
  await ref.read(Preferences.tikNetSmartLockedTag.notifier).update('');
  await ref.read(Preferences.tikNetSmartLockedGroup.notifier).update('');
}

/// After VPN is Connected with smart selection: urltest all nodes, pick lowest ping,
/// lock that outbound for the session (until disconnect / reconnect).
Future<void> applyTikNetSmartConnect(WidgetRef ref) async {
  if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) return;

  final lockedTag = ref.read(Preferences.tikNetSmartLockedTag).trim();
  final lockedGroup = ref.read(Preferences.tikNetSmartLockedGroup).trim();
  if (lockedTag.isNotEmpty) {
    await _selectOutbound(ref, groupTag: lockedGroup, outboundTag: lockedTag, reason: 'smart-locked');
    return;
  }

  ref.read(tikNetSmartPickingProvider.notifier).state = true;
  try {
    // Measuring takes ~20s. Until it finishes the core routes through its own
    // `balance` default, which round-robins over dead outbounds, so park traffic
    // on the lowest-delay group first.
    await ensureSafeDefaultOutbound(
      ref.read(proxyRepositoryProvider),
      reason: 'smart-measuring',
    );

    final nodesState = await ref.read(personalOutboundProvider.future).timeout(
      const Duration(seconds: 20),
      onTimeout: () => const TikNetPersonalNodesState(catalog: null, nodePings: {}),
    );
    final catalog = nodesState.catalog;
    if (catalog == null || catalog.nodes.isEmpty) {
      TikNetDiagnosticLog.w('smart', 'no nodes for smart connect');
      return;
    }

    // Brief pause scaled by node count (feels intentional; keeps UI calm).
    final pauseMs = (800 + catalog.nodes.length * 120).clamp(800, 4500);
    await Future<void>.delayed(Duration(milliseconds: pauseMs));

    if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) return;

    final pings = await ref
        .read(tikNetClientPingServiceProvider)
        .measureNodePingsFromCore(catalog)
        .timeout(const Duration(seconds: 14), onTimeout: () => const {});

    final best = pickBestNodeByPing(catalog.nodes, pings);
    if (best == null) {
      // Nothing measured at all — leave the lowest-delay group installed above
      // rather than locking onto an arbitrary node that may be one of the dead ones.
      TikNetDiagnosticLog.w('smart', 'no measurable node; staying on lowest-delay group', {
        'nodes': catalog.nodes.length,
      });
      return;
    }

    TikNetDiagnosticLog.i('smart', 'picked lowest ping', {
      'tag': best.tag,
      'ms': best.pingMs,
      'approximate': best.approximate,
    });

    await ref.read(Preferences.tikNetSmartLockedTag.notifier).update(best.tag);
    await ref.read(Preferences.tikNetSmartLockedGroup.notifier).update(best.groupTag);
    await _selectOutbound(
      ref,
      groupTag: best.groupTag,
      outboundTag: best.tag,
      reason: 'smart-pick',
    );
  } catch (e) {
    TikNetDiagnosticLog.w('smart', 'smart connect failed', {'error': e.toString()});
  } finally {
    ref.read(tikNetSmartPickingProvider.notifier).state = false;
  }
}

/// Winning node of a smart pick.
typedef TikNetSmartPick = ({String tag, String groupTag, int pingMs, bool approximate});

/// Lowest-latency node, preferring real proxied measurements.
///
/// A raw-TCP estimate only measures the hop to the server: a node whose REALITY
/// handshake always fails still reports ~50 ms that way, which used to make it
/// win every time. Approximate results are therefore only considered when no
/// node has a real measurement.
TikNetSmartPick? pickBestNodeByPing(
  List<TikNetPersonalProxyNode> nodes,
  Map<String, TikNetClientPingResult> pings,
) {
  TikNetSmartPick? best;
  TikNetSmartPick? bestApproximate;

  for (final node in nodes) {
    final ping = pings[node.tag];
    final ms = ping?.pingMs;
    if (ping == null || !ping.reachable || ms == null || ms <= 0 || ms >= 65000) continue;
    final candidate = (
      tag: node.tag,
      groupTag: node.groupTag.trim(),
      pingMs: ms,
      approximate: ping.approximate,
    );
    if (ping.approximate) {
      if (bestApproximate == null || ms < bestApproximate.pingMs) bestApproximate = candidate;
    } else {
      if (best == null || ms < best.pingMs) best = candidate;
    }
  }

  return best ?? bestApproximate;
}

Future<void> _selectOutbound(
  WidgetRef ref, {
  required String groupTag,
  required String outboundTag,
  required String reason,
}) async {
  await selectOutboundInCore(
    ref.read(proxyRepositoryProvider),
    outboundTag: outboundTag,
    preferredGroupTag: groupTag,
    reason: reason,
  );
}
