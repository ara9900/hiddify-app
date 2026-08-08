import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';
import 'package:hiddify/features/tiknet/service/tiknet_core_selection.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/features/tiknet/service/tiknet_smart_connect.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ConnectionStatus? _connectionStatus(WidgetRef ref) {
  return switch (ref.read(connectionNotifierProvider)) {
    AsyncData<ConnectionStatus>(value: final status) => status,
    _ => null,
  };
}

Future<void> _abortWrongCatalogExit(WidgetRef ref, {required int catalogId, required String reason}) async {
  TikNetDiagnosticLog.w('select', reason, {'id': catalogId});
  try {
    await ref.read(syncServiceProvider).setSelectedServer(smartSelection());
  } catch (_) {}
  try {
    await ref.read(connectionNotifierProvider.notifier).abortConnection();
  } catch (e) {
    TikNetDiagnosticLog.w('select', 'abort after catalog miss failed', {'err': e.toString()});
  }
}

/// After profile load / connect, apply smart / proxy / legacy catalog pick via core API.
Future<void> applyTikNetPersonalOutboundSelection(WidgetRef ref) async {
  try {
    var selection = parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
    if (_connectionStatus(ref) is! Connected) return;
    if (!selectionNeedsOutboundApply(selection)) return;

    final sync = ref.read(syncServiceProvider);
    final entitlement = sync.currentEntitlement();
    if (entitlement.blocksCatalog && selectionUsesCatalog(selection)) {
      await clearTikNetSmartLockWidget(ref);
      await sync.setSelectedServer(smartSelection());
      await applyTikNetSmartConnect(ref);
      return;
    }

    // Legacy cat:{id} → merged outbound tag (same profile, selectProxy only).
    if (!selection.isPersonal && selection.catalogId != null) {
      final catalogId = selection.catalogId!;
      var nodesState = await ref.read(personalOutboundProvider.future).timeout(
        const Duration(seconds: 12),
        onTimeout: () => const TikNetPersonalNodesState(catalog: null, nodePings: {}),
      );
      var node = resolveCatalogSelectionToNode(selection, nodesState.catalog);
      if (node == null) {
        TikNetDiagnosticLog.w('select', 'catalog node missing — ensuring profile', {'id': catalogId});
        final ok = await sync.ensureCatalogServerInProfile(catalogId);
        try {
          ref.invalidate(personalOutboundProvider);
        } catch (_) {}
        if (!ok) {
          await _abortWrongCatalogExit(
            ref,
            catalogId: catalogId,
            reason: 'catalog still missing after inject — abort wrong exit',
          );
          return;
        }
        nodesState = await ref.read(personalOutboundProvider.future).timeout(
          const Duration(seconds: 12),
          onTimeout: () => const TikNetPersonalNodesState(catalog: null, nodePings: {}),
        );
        node = resolveCatalogSelectionToNode(selection, nodesState.catalog);
        if (node == null) {
          await _abortWrongCatalogExit(
            ref,
            catalogId: catalogId,
            reason: 'catalog meta missing after inject',
          );
          return;
        }
      }
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
    if (entitlement.blocksCatalog && isTikNetCatalogOutboundTag(outboundTag)) {
      await clearTikNetSmartLockWidget(ref);
      await sync.setSelectedServer(smartSelection());
      await applyTikNetSmartConnect(ref);
      return;
    }

    // Manual pick: clear any smart session lock.
    await clearTikNetSmartLockWidget(ref);

    final applied = await selectOutboundInCore(
      ref.read(proxyRepositoryProvider),
      outboundTag: outboundTag,
      preferredGroupTag: groupTag,
      reason: 'manual-pick',
    );
    if (!applied) {
      // After profile remerge, stored tags can go stale (e.g. old "WG § 5" vs
      // "TikNet-alireza § 7"). Resolve by stripped label before giving up.
      final nodesState = await ref.read(personalOutboundProvider.future).timeout(
        const Duration(seconds: 8),
        onTimeout: () => const TikNetPersonalNodesState(catalog: null, nodePings: {}),
      );
      final want = stripHiddifyTagSuffix(outboundTag);
      TikNetPersonalProxyNode? alt;
      final nodes = nodesState.catalog?.nodes ?? const <TikNetPersonalProxyNode>[];
      for (final n in nodes) {
        if (n.tag == outboundTag ||
            stripHiddifyTagSuffix(n.tag) == want ||
            n.displayLabel == want ||
            n.displayLabel == outboundTag) {
          alt = n;
          break;
        }
      }
      // Legacy short labels like "WG § 5" after remerge renamed the endpoint.
      if (alt == null && want.toUpperCase().contains('WG')) {
        for (final n in nodes) {
          if (n.protocol == 'wireguard') {
            alt = n;
            break;
          }
        }
      }
      var recovered = false;
      if (alt != null && alt.tag != outboundTag) {
        recovered = await selectOutboundInCore(
          ref.read(proxyRepositoryProvider),
          outboundTag: alt.tag,
          preferredGroupTag: alt.groupTag,
          reason: 'manual-pick-stale-tag',
        );
        if (recovered) {
          await sync.setSelectedServer((
            isPersonal: true,
            catalogId: null,
            personalKind: TikNetPersonalPickKind.proxy,
            personalTag: alt.tag,
            personalGroupTag: alt.groupTag,
          ));
        }
      }
      if (!recovered) {
        TikNetDiagnosticLog.w('select', 'manual outbound rejected by core', {
          'tag': outboundTag,
          'group': groupTag,
        });
        // Catalog manual picks must not silently land on another country.
        if (isTikNetCatalogOutboundTag(outboundTag)) {
          await ref.read(connectionNotifierProvider.notifier).abortConnection();
          return;
        }
        await ensureSafeDefaultOutbound(
          ref.read(proxyRepositoryProvider),
          reason: 'manual-pick-rejected',
        );
      }
    }
  } catch (e) {
    TikNetDiagnosticLog.e('select', 'apply outbound selection failed', {'err': e.toString()});
  }
}
