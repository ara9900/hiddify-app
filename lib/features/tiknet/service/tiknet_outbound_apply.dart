import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_core_selection.dart';
import 'package:hiddify/features/tiknet/service/tiknet_smart_connect.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ConnectionStatus? _connectionStatus(WidgetRef ref) {
  return switch (ref.read(connectionNotifierProvider)) {
    AsyncData<ConnectionStatus>(value: final status) => status,
    _ => null,
  };
}

/// After profile load / connect, apply smart / proxy / legacy catalog pick via core API.
Future<void> applyTikNetPersonalOutboundSelection(WidgetRef ref) async {
  var selection = parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
  if (_connectionStatus(ref) is! Connected) return;
  if (!selectionNeedsOutboundApply(selection)) return;

  // Legacy cat:{id} → merged outbound tag (same profile, selectProxy only).
  if (!selection.isPersonal && selection.catalogId != null) {
    final nodesState = await ref.read(personalOutboundProvider.future).timeout(
      const Duration(seconds: 12),
      onTimeout: () => const TikNetPersonalNodesState(catalog: null, nodePings: {}),
    );
    final node = resolveCatalogSelectionToNode(selection, nodesState.catalog);
    if (node == null) return;
    selection = (
      isPersonal: true,
      catalogId: null,
      personalKind: TikNetPersonalPickKind.proxy,
      personalTag: node.tag,
      personalGroupTag: node.groupTag,
    );
  }

  if (!selection.isPersonal || selection.catalogId != null) return;

  if (selectionIsSmart(selection)) {
    await applyTikNetSmartConnect(ref);
    return;
  }

  final groupTag = (selection.personalGroupTag ?? '').trim();
  final outboundTag = (selection.personalTag ?? '').trim();
  if (outboundTag.isEmpty) return;

  // Manual pick: clear any smart session lock.
  await clearTikNetSmartLockWidget(ref);

  final applied = await selectOutboundInCore(
    ref.read(proxyRepositoryProvider),
    outboundTag: outboundTag,
    preferredGroupTag: groupTag,
    reason: 'manual-pick',
  );
  if (!applied) {
    // Better the lowest-delay group than the core's round-robin default.
    await ensureSafeDefaultOutbound(
      ref.read(proxyRepositoryProvider),
      reason: 'manual-pick-rejected',
    );
  }
}
