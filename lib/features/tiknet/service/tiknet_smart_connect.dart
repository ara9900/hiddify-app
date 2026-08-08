import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_core_selection.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// True while smart-connect is selecting the urltest/auto group.
final tikNetSmartPickingProvider = StateProvider<bool>((ref) => false);

Future<void> clearTikNetSmartLock(Ref ref) async {
  await ref.read(Preferences.tikNetSmartLockedTag.notifier).update('');
  await ref.read(Preferences.tikNetSmartLockedGroup.notifier).update('');
}

Future<void> clearTikNetSmartLockWidget(WidgetRef ref) async {
  await ref.read(Preferences.tikNetSmartLockedTag.notifier).update('');
  await ref.read(Preferences.tikNetSmartLockedGroup.notifier).update('');
}

/// After VPN is Connected with smart selection: park on the core urltest/auto
/// group (same behaviour as stock Hiddify "Auto") and let sing-box pick.
///
/// Previously we urltested every leaf, locked one tag for the session, and left
/// traffic on `balance` for ~20s — which caused dead-node locks and slow starts.
Future<void> applyTikNetSmartConnect(WidgetRef ref) async {
  if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) return;

  // Drop any legacy per-node lock from older builds.
  final lockedTag = ref.read(Preferences.tikNetSmartLockedTag).trim();
  if (lockedTag.isNotEmpty) {
    await clearTikNetSmartLockWidget(ref);
  }

  ref.read(tikNetSmartPickingProvider.notifier).state = true;
  try {
    final ok = await ensureSafeDefaultOutbound(
      ref.read(proxyRepositoryProvider),
      reason: 'smart-urltest',
    );
    TikNetDiagnosticLog.i('smart', 'parked on core urltest/auto group', {
      'selected': ok,
    });
  } catch (e) {
    TikNetDiagnosticLog.w('smart', 'smart connect failed', {'error': e.toString()});
  } finally {
    ref.read(tikNetSmartPickingProvider.notifier).state = false;
  }
}

/// Winning node of a smart pick (kept for unit tests / optional UI).
typedef TikNetSmartPick = ({String tag, String groupTag, int pingMs, bool approximate});

/// Lowest-latency node, preferring real proxied measurements.
///
/// A raw-TCP estimate only measures the hop to the server: a node whose REALITY
/// handshake always fails still reports ~50 ms that way, which used to make it
/// win every time. Approximate results are therefore only considered when no
/// node has a real measurement.
TikNetSmartPick? pickBestNodeByPing(
  List<TikNetPersonalProxyNode> nodes,
  Map<String, TikNetClientPingResult> pings, {
  bool excludeCatalog = false,
}) {
  TikNetSmartPick? best;
  TikNetSmartPick? bestApproximate;

  for (final node in nodes) {
    if (excludeCatalog && node.isCatalog) continue;
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
