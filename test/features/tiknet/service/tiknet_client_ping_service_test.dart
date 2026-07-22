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

  test('measureNodesTcp marks reachable, unreachable, and noTarget', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close();
    });
    server.listen((socket) {
      socket.destroy();
    });

    // Bind then close to get a port that refuses connections quickly.
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = closed.port;
    await closed.close();

    final nodes = [
      TikNetPersonalProxyNode(
        tag: 'ok',
        groupTag: 'Select',
        label: 'ok',
        probeUrl: 'https://127.0.0.1:${server.port}',
      ),
      TikNetPersonalProxyNode(
        tag: 'bad',
        groupTag: 'Select',
        label: 'bad',
        probeUrl: 'https://127.0.0.1:$closedPort',
      ),
      const TikNetPersonalProxyNode(
        tag: 'none',
        groupTag: 'Select',
        label: 'none',
        probeUrl: '',
      ),
    ];

    final results = await measureNodesTcp(
      nodes,
      timeout: const Duration(seconds: 2),
      concurrency: 3,
    );

    expect(results['ok']?.state, TikNetClientPingState.reachable);
    expect(results['ok']?.pingMs, greaterThan(0));
    expect(results['bad']?.state, TikNetClientPingState.unreachable);
    expect(results['none']?.state, TikNetClientPingState.noTarget);
  });
}
