import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Best sing-box group tag for urltest.
///
/// Prefer a dedicated `urltest` group when present (lists leaf proxies). Otherwise
/// the main selector — same group the proxies UI tests via `urlTest("select")`.
String urlTestGroupTagForCatalog(TikNetPersonalOutboundCatalog catalog) {
  for (final mode in catalog.autoModes) {
    if (mode.kind == TikNetPersonalPickKind.urltest && mode.tag.trim().isNotEmpty) {
      return mode.tag.trim();
    }
  }
  final main = catalog.mainGroupTag.trim();
  if (main.isNotEmpty) return main;
  if (catalog.nodes.isNotEmpty) return catalog.nodes.first.groupTag.trim();
  return '';
}

/// Pick the outbound group whose items overlap [wanted] tags the most.
/// Avoids urltesting an empty/stale "auto" that never lists catalog Reality leaves.
String resolveUrlTestGroupTag({
  required TikNetPersonalOutboundCatalog catalog,
  required Iterable<OutboundGroup> groups,
  required Set<String> wanted,
}) {
  String best = urlTestGroupTagForCatalog(catalog);
  var bestScore = -1;
  for (final group in groups) {
    final tag = group.tag.trim();
    if (tag.isEmpty) continue;
    var score = 0;
    for (final item in group.items) {
      final t = item.tag.trim();
      if (wanted.contains(t)) score++;
    }
    // Prefer dedicated urltest groups on ties.
    final isUrltest = catalog.autoModes.any(
      (m) => m.kind == TikNetPersonalPickKind.urltest && m.tag.trim() == tag,
    );
    final adjusted = score * 10 + (isUrltest ? 2 : 0) + (tag == catalog.mainGroupTag.trim() ? 1 : 0);
    if (adjusted > bestScore) {
      bestScore = adjusted;
      best = tag;
    }
  }
  return best.isNotEmpty ? best : urlTestGroupTagForCatalog(catalog);
}

/// Merge urlTestDelay from every group; prefer a real result over 0 / stale fail.
Map<String, int> delayByTagFromGroups(Iterable<OutboundGroup> groups) {
  final out = <String, int>{};
  for (final group in groups) {
    for (final item in group.items) {
      final tag = item.tag.trim();
      if (tag.isEmpty) continue;
      final delay = item.urlTestDelay;
      final prev = out[tag];
      if (prev == null) {
        out[tag] = delay;
        continue;
      }
      // Prefer a successful measurement.
      if (delay > 0 && delay < 65000) {
        out[tag] = delay;
        continue;
      }
      // Prefer any completed result (incl. fail) over "not tested yet" (0).
      if (prev == 0 && delay != 0) {
        out[tag] = delay;
      }
    }
  }
  return out;
}

/// Tags that exist as items under [groupTag] (or all groups if empty).
Set<String> tagsInGroup(Iterable<OutboundGroup> groups, String groupTag) {
  final wantedGroup = groupTag.trim();
  final out = <String>{};
  for (final group in groups) {
    if (wantedGroup.isNotEmpty && group.tag.trim() != wantedGroup) continue;
    for (final item in group.items) {
      final t = item.tag.trim();
      if (t.isNotEmpty) out.add(t);
    }
  }
  return out;
}

/// True when every [wanted] tag that is actually a member of the tested set has a non-zero delay.
/// Tags never present in the group are ignored (avoids waiting forever for Reality leaves
/// that were missing from urltest before the merger fix).
bool urlTestDelaysSettled(Map<String, int> delays, Set<String> wanted, {Set<String>? members}) {
  final scope = members == null || members.isEmpty ? wanted : wanted.intersection(members);
  if (scope.isEmpty) {
    // Nothing to wait for in this group — treat as settled so we can read snapshot.
    return wanted.isEmpty || delays.isNotEmpty;
  }
  for (final tag in scope) {
    final d = delays[tag];
    if (d == null || d == 0) return false;
  }
  return true;
}

/// Latency via sing-box urltest when core is up (user VPN or temporary probe).
class TikNetClientPingService {
  TikNetClientPingService(this._ref);

  final Ref _ref;

  /// Panel catalog list entries are not used for ping display anymore (merged outbounds use core urltest).
  TikNetServerCatalog catalogWithoutClientPing(TikNetServerCatalog catalog) {
    final servers = catalog.servers
        .map(
          (s) => s.copyWithClientPing(state: TikNetClientPingState.noTarget),
        )
        .toList();
    return TikNetServerCatalog(
      personalAvailable: catalog.personalAvailable,
      servers: servers,
      displayMode: catalog.displayMode,
    );
  }

  /// HTTP HEAD/GET to each node's probe URL (works without VPN / core).
  Future<Map<String, TikNetClientPingResult>> measureNodePingsHttp(
    TikNetPersonalOutboundCatalog catalog, {
    Duration timeout = const Duration(seconds: 3),
    int concurrency = 4,
  }) {
    return measureNodesHttp(catalog.nodes, timeout: timeout, concurrency: concurrency);
  }

  /// urltest on [groupTag] then read [OutboundInfo.urlTestDelay] per node tag.
  ///
  /// When [skipServiceCheck] is true (probe already waited for core Connected),
  /// skips [serviceRunningProvider] — needed because probe remaps UI to Disconnected.
  ///
  /// Waits for delays to leave 0 (urlTest often finishes updating via stream after
  /// the RPC returns). Treating delay==0 as "قطع" caused Reality false-negatives.
  Future<Map<String, TikNetClientPingResult>> measureNodePingsFromCore(
    TikNetPersonalOutboundCatalog catalog, {
    bool skipServiceCheck = false,
  }) async {
    final nodes = catalog.nodes;
    if (nodes.isEmpty) return const {};

    if (!skipServiceCheck) {
      final running = await _ref.read(serviceRunningProvider.future).catchError((_) => false);
      if (!running) return const {};
    }

    var groupTag = urlTestGroupTagForCatalog(catalog);
    if (groupTag.isEmpty) return const {};

    final wanted = {
      for (final n in nodes)
        if (n.tag.trim().isNotEmpty) n.tag.trim(),
    };
    if (wanted.isEmpty) return const {};

    final testUrl = _ref.read(ConfigOptions.connectionTestUrl);
    TikNetDiagnosticLog.i('ping', 'urltest start', {
      'url': testUrl,
      'group': groupTag,
      'nodes': wanted.length,
      'probe': skipServiceCheck,
    });

    final repo = _ref.read(proxyRepositoryProvider);
    final settled = Completer<Map<String, int>>();
    var latest = <String, int>{};
    var members = <String>{};

    void ingestGroups(List<OutboundGroup> groups) {
      groupTag = resolveUrlTestGroupTag(catalog: catalog, groups: groups, wanted: wanted);
      members = tagsInGroup(groups, groupTag);
      if (members.isEmpty) {
        members = tagsInGroup(groups, catalog.mainGroupTag);
      }
      latest = delayByTagFromGroups(groups);
      if (!settled.isCompleted && urlTestDelaysSettled(latest, wanted, members: members)) {
        settled.complete(Map<String, int>.from(latest));
      }
    }

    final sub = repo.watchAllProxies().listen((event) {
      final groups = event.fold<List<OutboundGroup>?>((_) => null, (g) => g);
      if (groups == null || groups.isEmpty) return;
      ingestGroups(groups);
    });

    try {
      // Reality handshakes are slow; allow the core RPC to finish testing the group.
      try {
        final warm = await repo.watchAllProxies().first.timeout(const Duration(seconds: 5));
        final warmGroups = warm.fold<List<OutboundGroup>?>((_) => null, (g) => g);
        if (warmGroups != null && warmGroups.isNotEmpty) {
          ingestGroups(warmGroups);
        }
        TikNetDiagnosticLog.i('ping', 'urltest group resolved', {
          'group': groupTag,
          'wanted': wanted.length,
          'members': members.length,
        });
        await repo.urlTest(groupTag).getOrElse((_) => unit).run().timeout(const Duration(seconds: 45));
        // Also test selector if urltest group didn't cover all leaves.
        final main = catalog.mainGroupTag.trim();
        if (main.isNotEmpty && main != groupTag) {
          await repo.urlTest(main).getOrElse((_) => unit).run().timeout(const Duration(seconds: 45));
        }
      } on TimeoutException {
        // Still try to read whatever delays the stream already has.
      } catch (_) {
        // Same — fall through to stream wait / latest snapshot.
      }

      final delays = await settled.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () => Map<String, int>.from(latest),
      );
      var result = _delaysFromMap(delays, nodes);
      // Stock AAR often fails Reality urltest (65000) while dial still works.
      // TCP to host:port upgrades false "قطع"; missing probe → "—" not قطع.
      result = await enrichUrlTestFailsWithTcp(result, nodes);
      final reachable = result.values.where((r) => r.state == TikNetClientPingState.reachable).length;
      final unreachable = result.values.where((r) => r.state == TikNetClientPingState.unreachable).length;
      final missing = result.values.where((r) => r.state == TikNetClientPingState.noTarget).length;
      TikNetDiagnosticLog.i('ping', 'urltest done', {
        'group': groupTag,
        'reachable': reachable,
        'unreachable': unreachable,
        'missing': missing,
      });
      return result;
    } finally {
      await sub.cancel();
    }
  }

  /// TCP connect to each node's host:port — never starts VPN.
  /// Kept for unit tests only; TikNet UI measure uses urltest (connected or probe).
  Future<Map<String, TikNetClientPingResult>> measureNodePingsTcp(
    TikNetPersonalOutboundCatalog catalog, {
    Duration timeout = const Duration(seconds: 3),
    int concurrency = 6,
  }) {
    return measureNodesTcp(catalog.nodes, timeout: timeout, concurrency: concurrency);
  }

  Map<String, TikNetClientPingResult> _delaysFromMap(
    Map<String, int> delayByTag,
    List<TikNetPersonalProxyNode> nodes,
  ) {
    return delaysToPingResults(delayByTag, nodes);
  }
}

/// Map urltest delays → ping results (pure; unit-testable).
Map<String, TikNetClientPingResult> delaysToPingResults(
  Map<String, int> delayByTag,
  List<TikNetPersonalProxyNode> nodes,
) {
  final out = <String, TikNetClientPingResult>{};
  for (final node in nodes) {
    final delay = delayByTag[node.tag];
    if (delay == null) {
      out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
      continue;
    }
    // 0 = not tested yet / unset — must NOT show as "قطع" (false negative).
    if (delay <= 0) {
      out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
      continue;
    }
    if (delay >= 65000) {
      // urltest timeout — may be a Reality false-negative; TCP enrich may upgrade.
      out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
      continue;
    }
    out[node.tag] = TikNetClientPingResult(
      state: TikNetClientPingState.reachable,
      pingMs: delay,
    );
  }
  return out;
}

/// For urltest failures (65000 / قطع): TCP-reach the probe host.
/// - TCP OK → show as reachable (port open; dial often works even when urltest fails)
/// - no probe URL → "—" (noTarget), never false قطع
/// - TCP fail → keep قطع
Future<Map<String, TikNetClientPingResult>> enrichUrlTestFailsWithTcp(
  Map<String, TikNetClientPingResult> results,
  List<TikNetPersonalProxyNode> nodes, {
  Duration timeout = const Duration(seconds: 3),
  int concurrency = 6,
  Future<Map<String, TikNetClientPingResult>> Function(
    List<TikNetPersonalProxyNode> nodes, {
    Duration timeout,
    int concurrency,
  })? tcpMeasure,
}) async {
  final need = <TikNetPersonalProxyNode>[];
  for (final node in nodes) {
    if (results[node.tag]?.state == TikNetClientPingState.unreachable) {
      need.add(node);
    }
  }
  if (need.isEmpty) return results;

  final measure = tcpMeasure ?? measureNodesTcp;
  final tcp = await measure(need, timeout: timeout, concurrency: concurrency);
  final out = Map<String, TikNetClientPingResult>.from(results);
  var upgraded = 0;
  var softened = 0;
  for (final node in need) {
    final t = tcp[node.tag];
    if (t == null) continue;
    if (t.state == TikNetClientPingState.reachable) {
      out[node.tag] = t;
      upgraded++;
    } else if (t.state == TikNetClientPingState.noTarget || parseProbeTarget(node.probeUrl) == null) {
      out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
      softened++;
    }
  }
  if (upgraded > 0 || softened > 0) {
    TikNetDiagnosticLog.i('ping', 'tcp fallback after urltest fail', {
      'candidates': need.length,
      'upgraded': upgraded,
      'softened': softened,
    });
  }
  return out;
}

/// Sort nodes by ping ascending (reachable first); missing / unreachable last.
List<TikNetPersonalProxyNode> sortNodesByPing(
  List<TikNetPersonalProxyNode> nodes,
  Map<String, TikNetClientPingResult> pings,
) {
  if (nodes.isEmpty || pings.isEmpty) return nodes;
  final copy = List<TikNetPersonalProxyNode>.from(nodes);
  int rank(TikNetClientPingResult? p) {
    if (p == null) return 3;
    return switch (p.state) {
      TikNetClientPingState.reachable => 0,
      TikNetClientPingState.measuring => 1,
      TikNetClientPingState.noTarget => 2,
      TikNetClientPingState.unreachable => 3,
    };
  }

  copy.sort((a, b) {
    final pa = pings[a.tag];
    final pb = pings[b.tag];
    final ra = rank(pa);
    final rb = rank(pb);
    if (ra != rb) return ra.compareTo(rb);
    // A raw-TCP estimate measures only the hop to the server, so it reads far
    // lower than a real proxied RTT. Never let one outrank a real measurement.
    final aa = pa?.approximate == true ? 1 : 0;
    final ab = pb?.approximate == true ? 1 : 0;
    if (aa != ab) return aa.compareTo(ab);
    final ma = pa?.pingMs ?? 1 << 30;
    final mb = pb?.pingMs ?? 1 << 30;
    final byMs = ma.compareTo(mb);
    if (byMs != 0) return byMs;
    return a.label.compareTo(b.label);
  });
  return copy;
}

/// Pure TCP reachability map (unit-testable; no VPN / core).
Future<Map<String, TikNetClientPingResult>> measureNodesTcp(
  List<TikNetPersonalProxyNode> nodes, {
  Duration timeout = const Duration(seconds: 3),
  int concurrency = 6,
}) async {
  if (nodes.isEmpty) return const {};
  final out = <String, TikNetClientPingResult>{};
  var index = 0;
  Future<void> worker() async {
    while (true) {
      final i = index++;
      if (i >= nodes.length) return;
      final node = nodes[i];
      final target = parseProbeTarget(node.probeUrl);
      if (target == null) {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
        continue;
      }
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(target.host, target.port, timeout: timeout);
        sw.stop();
        await socket.close();
        out[node.tag] = TikNetClientPingResult(
          state: TikNetClientPingState.reachable,
          pingMs: sw.elapsedMilliseconds.clamp(1, 60000),
          approximate: true,
        );
      } on SocketException {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
      } on TimeoutException {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
      } catch (_) {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
      }
    }
  }

  final workers = List.generate(concurrency.clamp(1, 16), (_) => worker());
  await Future.wait(workers);
  return out;
}

/// Pure HTTP reachability map (unit-testable without Riverpod / VPN core).
Future<Map<String, TikNetClientPingResult>> measureNodesHttp(
  List<TikNetPersonalProxyNode> nodes, {
  Duration timeout = const Duration(seconds: 3),
  int concurrency = 4,
  Future<TikNetClientPingResult> Function(String probeUrl, {Duration timeout})? probe,
}) async {
  if (nodes.isEmpty) return const {};
  final out = <String, TikNetClientPingResult>{};
  var next = 0;
  final workers = concurrency.clamp(1, 8);
  final run = probe ?? httpPingProbeUrl;

  Future<void> worker() async {
    while (true) {
      final i = next;
      next++;
      if (i >= nodes.length) return;
      final node = nodes[i];
      out[node.tag] = await run(node.probeUrl, timeout: timeout);
    }
  }

  await Future.wait(List.generate(workers, (_) => worker()));
  return out;
}

Future<TikNetClientPingResult> httpPingProbeUrl(
  String probeUrl, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final url = probeUrl.trim();
  if (url.isEmpty) {
    return const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
  }

  final dio = Dio(
    BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      followRedirects: true,
      validateStatus: (_) => true,
      responseType: ResponseType.bytes,
      headers: const {'User-Agent': 'TikNet-Ping/1.0'},
    ),
  );

  final sw = Stopwatch()..start();
  try {
    Response<List<int>> response;
    try {
      response = await dio.headUri(uri);
    } on DioException {
      response = await dio.getUri(uri);
    }
    sw.stop();
    // Any HTTP response means the endpoint answered.
    if (response.statusCode != null && response.statusCode! > 0) {
      return TikNetClientPingResult(
        state: TikNetClientPingState.reachable,
        pingMs: sw.elapsedMilliseconds.clamp(1, 60000),
      );
    }
    return const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
  } on DioException catch (e) {
    sw.stop();
    if (e.response?.statusCode != null && e.response!.statusCode! > 0) {
      return TikNetClientPingResult(
        state: TikNetClientPingState.reachable,
        pingMs: sw.elapsedMilliseconds.clamp(1, 60000),
      );
    }
    return const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
  } on SocketException {
    return const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
  } on TimeoutException {
    return const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
  } catch (_) {
    return const TikNetClientPingResult(state: TikNetClientPingState.unreachable);
  } finally {
    dio.close(force: true);
  }
}

final tikNetClientPingServiceProvider = Provider<TikNetClientPingService>(
  (ref) => TikNetClientPingService(ref),
);
