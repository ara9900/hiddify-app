import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Best sing-box group tag for urltest (selector or dedicated url-test group).
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

/// Latency via sing-box urltest when core is up; otherwise HTTP probe to outbound host.
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
  Future<Map<String, TikNetClientPingResult>> measureNodePingsFromCore(
    TikNetPersonalOutboundCatalog catalog,
  ) async {
    final nodes = catalog.nodes;
    if (nodes.isEmpty) return const {};

    final running = await _ref.read(serviceRunningProvider.future).catchError((_) => false);
    if (!running) return const {};

    final groupTag = urlTestGroupTagForCatalog(catalog);
    if (groupTag.isEmpty) return const {};

    try {
      await _ref
          .read(proxyRepositoryProvider)
          .urlTest(groupTag)
          .getOrElse((_) => unit)
          .run()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return const {};
    } catch (_) {
      return const {};
    }

    OutboundGroup? group;
    try {
      group = await _ref
          .read(proxyRepositoryProvider)
          .watchProxies()
          .map((e) => e.fold((_) => null, (g) => g))
          .where((g) => g != null)
          .map((g) => g!)
          .first
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return const {};
    } catch (_) {
      return const {};
    }

    return _delaysFromGroup(group, nodes);
  }

  /// TCP connect to each node's host:port — never starts VPN.
  Future<Map<String, TikNetClientPingResult>> measureNodePingsTcp(
    TikNetPersonalOutboundCatalog catalog, {
    Duration timeout = const Duration(seconds: 3),
    int concurrency = 6,
  }) {
    return measureNodesTcp(catalog.nodes, timeout: timeout, concurrency: concurrency);
  }

  Map<String, TikNetClientPingResult> _delaysFromGroup(
    OutboundGroup? group,
    List<TikNetPersonalProxyNode> nodes,
  ) {
    if (group == null) return const {};

    final delayByTag = <String, int>{
      for (final item in group.items)
        if (item.tag.isNotEmpty) item.tag: item.urlTestDelay,
    };

    final out = <String, TikNetClientPingResult>{};
    for (final node in nodes) {
      final delay = delayByTag[node.tag];
      if (delay == null) {
        out[node.tag] = const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
        continue;
      }
      if (delay <= 0 || delay >= 65000) {
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
