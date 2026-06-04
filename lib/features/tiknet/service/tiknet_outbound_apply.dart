import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ConnectionStatus? _connectionStatus(dynamic ref) {
  return switch (ref.read(connectionNotifierProvider)) {
    AsyncData<ConnectionStatus>(value: final status) => status,
    _ => null,
  };
}

/// After profile load / connect, apply personal urltest/balancer/proxy pick via core API.
Future<void> applyTikNetPersonalOutboundSelection(dynamic ref) async {
  final selection = parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
  if (!selection.isPersonal || selection.catalogId != null) return;

  if (_connectionStatus(ref) is! Connected) return;

  if (selection.personalKind == TikNetPersonalPickKind.defaultAuto) {
    const group = 'Select';
    const auto = 'Auto';
    await ref
        .read(proxyRepositoryProvider)
        .selectProxy(group, auto)
        .getOrElse((_) => unit)
        .run()
        .timeout(const Duration(seconds: 8), onTimeout: () {});
    return;
  }

  if (!selectionNeedsOutboundApply(selection)) return;

  var groupTag = (selection.personalGroupTag ?? '').trim();
  final outboundTag = (selection.personalTag ?? '').trim();
  if (groupTag.isEmpty) {
    groupTag = 'Select';
  }
  if (groupTag.isEmpty || outboundTag.isEmpty) return;

  await ref
      .read(proxyRepositoryProvider)
      .selectProxy(groupTag, outboundTag)
      .getOrElse((_) => unit)
      .run()
      .timeout(const Duration(seconds: 8), onTimeout: () {});
}
