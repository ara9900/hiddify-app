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

/// True when every [wanted] tag has a non-zero delay (success or fail sentinel).
bool urlTestDelaysSettled(Map<String, int> delays, Set<String> wanted) {
  if (wanted.isEmpty) return true;
  for (final tag in wanted) {
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
      personalPing: null,
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

    final groupTag = urlTestGroupTagForCatalog(catalog);
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

    final sub = repo.watchAllProxies().listen((event) {
      final groups = event.fold<List<OutboundGroup>?>((_) => null, (g) => g);
      if (groups == null || groups.isEmpty) return;
      latest = delayByTagFromGroups(groups);
      if (!settled.isCompleted && urlTestDelaysSettled(latest, wanted)) {
        settled.complete(Map<String, int>.from(latest));
      }
    });

    try {
      // Reality handshakes are slow; allow the core RPC to finish testing the group.
      try {
        await repo.urlTest(groupTag).getOrElse((_) => unit).run().timeout(const Duration(seconds: 35));
      } on TimeoutException {
        // Still try to read whatever delays the stream already has.
      } catch (_) {
        // Same — fall through to stream wait / latest snapshot.
      }

      final delays = await settled.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => Map<String, int>.from(latest),
      );
      return _delaysFromMap(delays, nodes);
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
