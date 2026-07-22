import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
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
    await _selectOutbound(ref, groupTag: lockedGroup.isEmpty ? 'Select' : lockedGroup, outboundTag: lockedTag);
    return;
  }

  ref.read(tikNetSmartPickingProvider.notifier).state = true;
  try {
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

    String? bestTag;
    String bestGroup = catalog.mainGroupTag.trim().isEmpty ? 'Select' : catalog.mainGroupTag.trim();
    var bestMs = 1 << 30;

    for (final node in catalog.nodes) {
      final ping = pings[node.tag];
      final ms = ping?.pingMs;
      if (ping == null || !ping.reachable || ms == null || ms <= 0 || ms >= 65000) continue;
      if (ms < bestMs) {
        bestMs = ms;
        bestTag = node.tag;
        bestGroup = node.groupTag.trim().isEmpty ? bestGroup : node.groupTag.trim();
      }
    }

    if (bestTag == null || bestTag.isEmpty) {
      // Fallback: first node (still sticky for this session).
      final first = catalog.nodes.first;
      bestTag = first.tag;
      bestGroup = first.groupTag.trim().isEmpty ? bestGroup : first.groupTag.trim();
      TikNetDiagnosticLog.w('smart', 'no reachable ping; fallback first node', {'tag': bestTag});
    } else {
      TikNetDiagnosticLog.i('smart', 'picked lowest ping', {'tag': bestTag, 'ms': bestMs});
    }

    final chosen = bestTag;
    if (chosen == null || chosen.isEmpty) return;

    await ref.read(Preferences.tikNetSmartLockedTag.notifier).update(chosen);
    await ref.read(Preferences.tikNetSmartLockedGroup.notifier).update(bestGroup);
    await _selectOutbound(ref, groupTag: bestGroup, outboundTag: chosen);
  } catch (e) {
    TikNetDiagnosticLog.w('smart', 'smart connect failed', {'error': e.toString()});
  } finally {
    ref.read(tikNetSmartPickingProvider.notifier).state = false;
  }
}

Future<void> _selectOutbound(
  WidgetRef ref, {
  required String groupTag,
  required String outboundTag,
}) async {
  final group = groupTag.trim().isEmpty ? 'Select' : groupTag.trim();
  final tag = outboundTag.trim();
  if (tag.isEmpty) return;
  await ref
      .read(proxyRepositoryProvider)
      .selectProxy(group, tag)
      .getOrElse((_) => unit)
      .run()
      .timeout(const Duration(seconds: 8), onTimeout: () => unit);
}
