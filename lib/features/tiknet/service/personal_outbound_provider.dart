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

  String? content;
  if (profileId.isNotEmpty) {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      final generated = await repo.generateConfig(profileId).run();
      generated.fold((_) {}, (c) {
        if (c.trim().isNotEmpty) content = c;
      });
    } catch (_) {}
  }

  if (content == null || content!.trim().isEmpty) {
    final rawB64 = ref.read(Preferences.tikNetCachedConfig);
    if (rawB64.isNotEmpty) {
      try {
        content = utf8.decode(base64Decode(rawB64));
      } catch (_) {}
    }
  }

  if (content == null || content!.trim().isEmpty) {
    return const TikNetPersonalNodesState(catalog: null, nodePings: {});
  }

  var catalog = parsePersonalOutboundsFromConfig(content!);
  String? hint;

  if (catalog == null || catalog.nodes.isEmpty) {
    catalog = parsePersonalOutboundsFromSubscriptionLinks(content!);
    if (catalog != null && catalog.nodes.isNotEmpty && profileId.isEmpty) {
      hint = 'برای انتخاب هر سرور، یک‌بار «بروزرسانی» در حساب من بزنید.';
    }
  }

  if (catalog == null || catalog.isEmpty) {
    return TikNetPersonalNodesState(
      catalog: null,
      nodePings: const {},
      parseHint: 'لیست کانفیگ از اشتراک خوانده نشد. از حساب من → بروزرسانی را بزنید.',
    );
  }

  final ping = ref.read(tikNetClientPingServiceProvider);
  final pings = <String, TikNetClientPingResult>{};
  for (final node in catalog.nodes) {
    pings[node.tag] = await ping.measureUrl(node.probeUrl.isEmpty ? null : node.probeUrl);
  }
  return TikNetPersonalNodesState(catalog: catalog, nodePings: pings, parseHint: hint);
});
