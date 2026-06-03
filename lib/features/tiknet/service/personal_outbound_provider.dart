import 'dart:convert';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TikNetPersonalNodesState {
  const TikNetPersonalNodesState({
    required this.catalog,
    required this.nodePings,
    this.parseHint,
  });

  final TikNetPersonalOutboundCatalog? catalog;
  final Map<String, TikNetClientPingResult> nodePings;
  final String? parseHint;
}

final personalOutboundProvider = FutureProvider<TikNetPersonalNodesState>((ref) async {
  ref.watch(Preferences.tikNetCachedConfig);
  ref.watch(Preferences.tikNetProfileId);

  var profileId = ref.read(Preferences.tikNetProfileId);
  if (profileId.isEmpty && ref.read(Preferences.tikNetCachedConfig).isNotEmpty) {
    await ref.read(syncServiceProvider).applyProfileFromCache();
    profileId = ref.read(Preferences.tikNetProfileId);
  }

  final candidates = <String>[];

  if (profileId.isNotEmpty) {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      final rawProfile = await repo.getRawConfig(profileId).run();
      rawProfile.fold((_) {}, (c) {
        if (c.trim().isNotEmpty) candidates.add(c);
      });
      final generated = await repo.generateConfig(profileId).run();
      generated.fold((_) {}, (c) {
        if (c.trim().isNotEmpty) candidates.add(c);
      });
    } catch (_) {}
  }

  final rawB64 = ref.read(Preferences.tikNetCachedConfig);
  if (rawB64.isNotEmpty) {
    try {
      final decoded = utf8.decode(base64Decode(rawB64));
      if (decoded.trim().isNotEmpty) candidates.add(decoded);
    } catch (_) {}
  }

  if (candidates.isEmpty) {
    return const TikNetPersonalNodesState(catalog: null, nodePings: {});
  }

  TikNetPersonalOutboundCatalog? catalog;
  String? hint;
  for (final raw in candidates) {
    catalog = parsePersonalOutboundsFromConfig(raw);
    if (catalog == null || catalog.nodes.isEmpty) {
      catalog = parsePersonalOutboundsFromSubscriptionLinks(raw);
    }
    if (catalog != null && !catalog.isEmpty) break;
  }

  if (catalog != null && catalog.nodes.isNotEmpty && profileId.isEmpty) {
    hint = 'برای انتخاب هر سرور، یک‌بار «بروزرسانی» در حساب من بزنید.';
  }

  if (catalog == null || catalog.isEmpty) {
    return TikNetPersonalNodesState(
      catalog: null,
      nodePings: const {},
      parseHint: 'لیست کانفیگ از اشتراک خوانده نشد. از حساب من → بروزرسانی را بزنید.',
    );
  }

  final ping = ref.read(tikNetClientPingServiceProvider);
  final pings = await ping.measureNodePings(catalog.nodes);
  return TikNetPersonalNodesState(catalog: catalog, nodePings: pings, parseHint: hint);
});
