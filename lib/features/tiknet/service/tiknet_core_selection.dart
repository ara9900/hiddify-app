import 'dart:async';

import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/tiknet/model/tiknet_core_tags.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

export 'package:hiddify/features/tiknet/model/tiknet_core_tags.dart';

/// Safe stand-ins for [kCoreBalanceTag], best first.
const _safeDefaultTags = [kCoreLowestTag, 'auto', 'urltest'];

const _selectorType = 'selector';

/// Group tag the core will actually accept when selecting [outboundTag].
///
/// Only a selector that lists the outbound can select it, so prefer those; a
/// [preferred] tag is honoured only when the live core confirms it exists.
String resolveSelectionGroupTag({
  required Iterable<OutboundGroup> groups,
  required String outboundTag,
  String preferred = '',
}) {
  final tag = outboundTag.trim();
  final want = preferred.trim();

  final selectors = [
    for (final g in groups)
      if (g.tag.trim().isNotEmpty && g.type.trim().toLowerCase() == _selectorType) g,
  ];

  final holders = [
    for (final g in selectors)
      if (g.items.any((i) => i.tag.trim() == tag)) g,
  ];

  String? pick(List<OutboundGroup> from) {
    if (from.isEmpty) return null;
    for (final g in from) {
      if (want.isNotEmpty && g.tag.trim() == want) return g.tag.trim();
    }
    for (final g in from) {
      if (g.tag.trim() == kCoreSelectorTag) return kCoreSelectorTag;
    }
    return from.first.tag.trim();
  }

  return pick(holders) ?? pick(selectors) ?? kCoreSelectorTag;
}

/// Outbound to install when the core is still defaulting to [kCoreBalanceTag].
///
/// Returns null when the selector already points somewhere sane, so callers can
/// avoid pointlessly re-selecting.
String? resolveSafeDefaultOutbound(Iterable<OutboundGroup> groups) {
  OutboundGroup? selector;
  for (final g in groups) {
    if (g.type.trim().toLowerCase() != _selectorType) continue;
    if (g.tag.trim() == kCoreSelectorTag) {
      selector = g;
      break;
    }
    selector ??= g;
  }
  if (selector == null) return null;

  final selected = selector.selected.trim();
  if (selected.isNotEmpty && selected != kCoreBalanceTag) return null;

  final items = {for (final i in selector.items) i.tag.trim()};
  for (final candidate in _safeDefaultTags) {
    if (items.contains(candidate)) return candidate;
  }
  return null;
}

/// Latest group list from the core, or empty when it cannot be read in time.
Future<List<OutboundGroup>> coreGroupsSnapshot(
  ProxyRepository repo, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    final event = await repo.watchAllProxies().first.timeout(timeout);
    return event.fold((_) => const <OutboundGroup>[], (g) => g);
  } catch (_) {
    return const <OutboundGroup>[];
  }
}

/// Select [outboundTag] in whichever group the live core exposes it under.
///
/// Returns whether the core accepted it. A rejected selection means traffic
/// stays on the core's own default, so it is always logged rather than swallowed.
Future<bool> selectOutboundInCore(
  ProxyRepository repo, {
  required String outboundTag,
  String preferredGroupTag = '',
  String reason = '',
  List<OutboundGroup>? groups,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final tag = outboundTag.trim();
  if (tag.isEmpty) return false;

  final live = groups ?? await coreGroupsSnapshot(repo);
  final group = resolveSelectionGroupTag(
    groups: live,
    outboundTag: tag,
    preferred: preferredGroupTag,
  );

  if (await _select(repo, group, tag, timeout)) {
    TikNetDiagnosticLog.i('select', 'outbound selected', {
      'group': group,
      'tag': tag,
      'why': reason,
    });
    return true;
  }

  if (group != kCoreSelectorTag && await _select(repo, kCoreSelectorTag, tag, timeout)) {
    TikNetDiagnosticLog.w('select', 'selected via core selector fallback', {
      'group': kCoreSelectorTag,
      'tag': tag,
      'rejected': group,
      'why': reason,
    });
    return true;
  }

  TikNetDiagnosticLog.e('select', 'select rejected — core kept its own default', {
    'group': group,
    'tag': tag,
    'why': reason,
    'liveGroups': live.map((g) => g.tag).join(','),
  });
  return false;
}

/// Move traffic off the round-robin `balance` default as soon as the core is up,
/// so nothing rides the dead outbounds while a real pick is still being measured.
Future<bool> ensureSafeDefaultOutbound(
  ProxyRepository repo, {
  String reason = 'post-connect',
}) async {
  final groups = await coreGroupsSnapshot(repo);
  final candidate = resolveSafeDefaultOutbound(groups);
  if (candidate == null) return false;
  return selectOutboundInCore(
    repo,
    outboundTag: candidate,
    reason: reason,
    groups: groups,
  );
}

Future<bool> _select(
  ProxyRepository repo,
  String group,
  String tag,
  Duration timeout,
) async {
  try {
    final result = await repo.selectProxy(group, tag).run().timeout(timeout);
    return result.isRight();
  } catch (_) {
    return false;
  }
}
