import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// After profile load / connect, apply personal urltest/balancer/proxy pick via core API.
Future<void> applyTikNetPersonalOutboundSelection(Ref ref) async {
  final selection = parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
  if (!selectionNeedsOutboundApply(selection)) return;

  final conn = ref.read(connectionNotifierProvider).valueOrNull;
  if (conn is! Connected) return;

  final groupTag = (selection.personalGroupTag ?? '').trim();
  final outboundTag = (selection.personalTag ?? '').trim();
  if (groupTag.isEmpty || outboundTag.isEmpty) return;

  final targetTag = switch (selection.personalKind) {
    TikNetPersonalPickKind.urltest => outboundTag,
    TikNetPersonalPickKind.balancer => outboundTag,
    TikNetPersonalPickKind.proxy => outboundTag,
    _ => outboundTag,
  };

  await ref.read(proxyRepositoryProvider).selectProxy(groupTag, targetTag).getOrElse((_) => unit).run();
}
