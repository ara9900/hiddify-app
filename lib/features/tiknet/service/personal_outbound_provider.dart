import 'dart:async';
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

  final rawB64 = ref.read(Preferences.tikNetCachedConfig);
  if (rawB64.isNotEmpty) {
    try {
      final decoded = utf8.decode(base64Decode(rawB64));
      if (decoded.trim().isNotEmpty) candidates.add(decoded);
    } catch (_) {}
  }

  if (profileId.isNotEmpty) {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      final rawProfile = await repo.getRawConfig(profileId).run();
      rawProfile.fold((_) {}, (c) {
        if (c.trim().isNotEmpty) candidates.add(c);
      });
      // Do not call generateConfig here — Hiddify xray bundles can hang the UI for minutes.
    } catch (_) {}
  }

  if (candidates.isEmpty) {
    return const TikNetPersonalNodesState(catalog: null, nodePings: {});
  }

  TikNetPersonalOutboundCatalog? catalog;
  String? hint;
  for (final raw in candidates) {
    final parsed = parsePersonalOutboundsFromAny(raw);
    if (parsed == null || parsed.isEmpty) continue;
    if (catalog == null || parsed.nodes.length > catalog.nodes.length) {
      catalog = parsed;
    }
    if (catalog!.nodes.isNotEmpty) break;
  }

  if (catalog == null || catalog.nodes.isEmpty) {
    final subUrl = normalizeSubscriptionFetchUrl(ref.read(Preferences.tikNetSubscriptionUrl));
    if (subUrl.toLowerCase().startsWith('http')) {
      var applied = false;
      try {
        applied = await ref
            .read(syncServiceProvider)
            .applyRemoteSubscriptionProfile()
            .timeout(const Duration(seconds: 40));
      } on TimeoutException {
        applied = false;
      }
      if (applied) {
        profileId = ref.read(Preferences.tikNetProfileId);
        if (profileId.isNotEmpty) {
          try {
            final repo = await ref.read(profileRepositoryProvider.future);
            final rawProfile = await repo.getRawConfig(profileId).run();
            rawProfile.fold((_) {}, (c) {
              if (c.trim().isEmpty) return;
              final parsed = parsePersonalOutboundsFromAny(c);
              if (parsed != null && (catalog == null || parsed.nodes.length > catalog!.nodes.length)) {
                catalog = parsed;
              }
            });
          } catch (_) {}
        }
      }
    }
  }

  final resolved = catalog;
  if (resolved != null && resolved.nodes.isNotEmpty && profileId.isEmpty) {
    hint = 'برای انتخاب هر سرور، یک‌بار «بروزرسانی» در حساب من بزنید.';
  }

  if (resolved == null || resolved.isEmpty) {
    return TikNetPersonalNodesState(
      catalog: null,
      nodePings: const {},
      parseHint: 'لیست کانفیگ از اشتراک خوانده نشد. از حساب من → بروزرسانی را بزنید.',
    );
  }

  // Never block the server picker on per-node pings (Hiddify subs can have 15+ nodes × 5s each).
  var pings = const <String, TikNetClientPingResult>{};
  if (resolved.nodes.length <= 6) {
    try {
      pings = await ref
          .read(tikNetClientPingServiceProvider)
          .measureNodePings(resolved.nodes)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      pings = const {};
    }
  }

  return TikNetPersonalNodesState(catalog: resolved, nodePings: pings, parseHint: hint);
});
