import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Measures reachability/latency from the user's device (ISP/regional path).
class TikNetClientPingService {
  static const _connectTimeout = Duration(seconds: 5);
  static const _maxConcurrent = 4;

  Future<TikNetServerCatalog> measureCatalog(
    TikNetServerCatalog catalog, {
    String? personalSubscriptionUrl,
  }) async {
    final servers = await _measureAll(catalog.servers);
    TikNetClientPingResult? personal;
    if (catalog.personalAvailable) {
      personal = await measureUrl(personalSubscriptionUrl);
    }
    return TikNetServerCatalog(
      personalAvailable: catalog.personalAvailable,
      servers: servers,
      personalPing: personal,
    );
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
  Future<TikNetClientPingResult> measureUrl(String? raw) async {
    final url = (raw ?? '').trim();
    if (url.isEmpty) {
      return const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return const TikNetClientPingResult(state: TikNetClientPingState.noTarget);
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
