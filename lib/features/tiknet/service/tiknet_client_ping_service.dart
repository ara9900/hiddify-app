import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Measures reachability/latency from the user's device (ISP/regional path).
class TikNetClientPingService {
  static const _connectTimeout = Duration(seconds: 5);
  static const _fastConnectTimeout = Duration(seconds: 2);
  static const _maxConcurrent = 4;

  Future<TikNetServerCatalog> measureCatalog(
    TikNetServerCatalog catalog, {
    String? personalSubscriptionUrl,
  }) async {
    final servers = await _measureAll(catalog.servers);
    TikNetClientPingResult? personal;
    // In personal_only mode, per-node pings run separately; skip slow subscription URL probe.
    if (catalog.personalAvailable &&
        catalog.displayMode != TikNetServerDisplayMode.personalOnly) {
      personal = await measureUrl(personalSubscriptionUrl);
    }
    return TikNetServerCatalog(
      personalAvailable: catalog.personalAvailable,
      servers: servers,
      personalPing: personal,
      displayMode: catalog.displayMode,
    );
  }

  /// Parallel pings for personal subscription nodes (bounded concurrency).
  Future<Map<String, TikNetClientPingResult>> measureNodePings(
    List<TikNetPersonalProxyNode> nodes, {
    bool fast = false,
  }) async {
    if (nodes.isEmpty) return const {};
    final out = <String, TikNetClientPingResult>{};
    var index = 0;
    final toMeasure = fast && nodes.length > 12 ? nodes.take(12).toList() : nodes;

    Future<void> worker() async {
      while (true) {
        final i = index;
        index++;
        if (i >= toMeasure.length) return;
        final node = toMeasure[i];
        out[node.tag] = await measureUrl(
          node.probeUrl.isEmpty ? null : node.probeUrl,
          fast: fast,
        );
      }
    }

    final workers = List.generate(
      nodes.length < _maxConcurrent ? nodes.length : _maxConcurrent,
      (_) => worker(),
    );
    await Future.wait(workers);
    return out;
  }

  Future<List<TikNetServerEntry>> _measureAll(List<TikNetServerEntry> servers) async {
    if (servers.isEmpty) return servers;

    final out = List<TikNetServerEntry?>.filled(servers.length, null);
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final i = index;
        index++;
        if (i >= servers.length) return;
        final s = servers[i];
        if (s.probeUrl.isEmpty) {
          out[i] = s.copyWithClientPing(state: TikNetClientPingState.noTarget);
          continue;
        }
        out[i] = s.copyWithClientPing(state: TikNetClientPingState.measuring);
        final result = await measureUrl(s.probeUrl);
        out[i] = s.copyWithClientPing(
          state: result.reachable ? TikNetClientPingState.reachable : TikNetClientPingState.unreachable,
          pingMs: result.pingMs,
        );
      }
    }

    final workers = List.generate(
      servers.length < _maxConcurrent ? servers.length : _maxConcurrent,
      (_) => worker(),
    );
    await Future.wait(workers);
    return out.whereType<TikNetServerEntry>().toList();
  }

  /// HTTP HEAD then TCP :443 fallback. [pingMs] is -1 when unreachable.
  Future<TikNetClientPingResult> measureUrl(String? raw, {bool fast = false}) async {
    final url = (raw ?? '').trim();
    if (url.isEmpty) {
      return const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
    }

    if (fast) {
      final sw = Stopwatch()..start();
      try {
        final port = uri.hasPort ? uri.port : 443;
        final socket = await Socket.connect(uri.host, port, timeout: _fastConnectTimeout);
        await socket.close();
        sw.stop();
        return TikNetClientPingResult(
          state: TikNetClientPingState.reachable,
          pingMs: sw.elapsedMilliseconds,
          tcpProbeOnly: true,
        );
      } catch (_) {
        return const TikNetClientPingResult(
          state: TikNetClientPingState.unreachable,
          pingMs: -1,
          tcpProbeOnly: true,
        );
      }
    }

    final target = uri.hasScheme ? url : 'https://$url';
    final parsed = Uri.parse(target);
    final sw = Stopwatch()..start();

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: _connectTimeout,
          receiveTimeout: _connectTimeout,
          sendTimeout: _connectTimeout,
          followRedirects: true,
          validateStatus: (code) => code != null && code < 500,
          headers: const {'User-Agent': 'TikNet-App-Ping/1.0'},
        ),
      );
      await dio.head(parsed.toString());
      sw.stop();
      return TikNetClientPingResult(
        state: TikNetClientPingState.reachable,
        pingMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      // Many nodes block HEAD; try GET with range
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: _connectTimeout,
            receiveTimeout: _connectTimeout,
            followRedirects: true,
            validateStatus: (code) => code != null && code < 500,
            headers: const {'User-Agent': 'TikNet-App-Ping/1.0'},
          ),
        );
        await dio.get<dynamic>(
          parsed.toString(),
          options: Options(responseType: ResponseType.bytes),
        );
        sw.stop();
        return TikNetClientPingResult(
          state: TikNetClientPingState.reachable,
          pingMs: sw.elapsedMilliseconds,
        );
      } catch (_) {}
    }

    sw.reset();
    sw.start();
    try {
      final port = parsed.hasPort ? parsed.port : 443;
      final socket = await Socket.connect(
        parsed.host,
        port,
        timeout: _connectTimeout,
      );
      await socket.close();
      sw.stop();
      return TikNetClientPingResult(
        state: TikNetClientPingState.reachable,
        pingMs: sw.elapsedMilliseconds,
      );
    } catch (_) {
      return const TikNetClientPingResult(
        state: TikNetClientPingState.unreachable,
        pingMs: -1,
      );
    }
  }
}

final tikNetClientPingServiceProvider = Provider<TikNetClientPingService>(
  (ref) => TikNetClientPingService(),
);
