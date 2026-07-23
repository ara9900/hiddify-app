import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('catalogWithoutClientPing preserves displayMode from input catalog', () {
    const catalog = TikNetServerCatalog(
      personalAvailable: true,
      servers: [],
      displayMode: TikNetServerDisplayMode.personalOnly,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(tikNetClientPingServiceProvider);
    final result = service.catalogWithoutClientPing(catalog);
    expect(result.displayMode, TikNetServerDisplayMode.personalOnly);
  });

  test('parseProbeTarget reads host and non-default port', () {
    expect(parseProbeTarget(''), isNull);
    expect(parseProbeTarget('https://de.example.com:8443'), (host: 'de.example.com', port: 8443));
    expect(parseProbeTarget('https://de.example.com'), (host: 'de.example.com', port: 443));
  });

  test('measureNodesHttp marks reachable, unreachable, and noTarget', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      request.response.statusCode = 204;
      await request.response.close();
    });

    final nodes = [
      TikNetPersonalProxyNode(
        tag: 'ok',
        groupTag: 'Select',
        label: 'ok',
        probeUrl: 'http://127.0.0.1:${server.port}/',
      ),
      const TikNetPersonalProxyNode(
        tag: 'bad',
        groupTag: 'Select',
        label: 'bad',
        probeUrl: 'http://127.0.0.1:1/',
      ),
      const TikNetPersonalProxyNode(
        tag: 'none',
        groupTag: 'Select',
        label: 'none',
        probeUrl: '',
      ),
    ];

    final results = await measureNodesHttp(
      nodes,
      timeout: const Duration(seconds: 2),
      concurrency: 3,
    );

    expect(results['ok']?.state, TikNetClientPingState.reachable);
    expect(results['ok']?.pingMs, greaterThan(0));
    expect(results['bad']?.state, TikNetClientPingState.unreachable);
    expect(results['none']?.state, TikNetClientPingState.noTarget);
  });

  test('sortNodesByPing orders low latency first', () {
    const nodes = [
      TikNetPersonalProxyNode(tag: 'slow', groupTag: 'Select', label: 'slow'),
      TikNetPersonalProxyNode(tag: 'fast', groupTag: 'Select', label: 'fast'),
      TikNetPersonalProxyNode(tag: 'dead', groupTag: 'Select', label: 'dead'),
    ];
    final pings = {
      'slow': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 300),
      'fast': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 40),
      'dead': const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
    };
    final sorted = sortNodesByPing(nodes, pings);
    expect(sorted.map((n) => n.tag).toList(), ['fast', 'slow', 'dead']);
  });
}
