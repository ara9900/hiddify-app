import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
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
    server.listen((socket) async {
      await socket.close();
    });

    final nodes = [
      TikNetPersonalProxyNode(
        tag: 'ok',
        groupTag: 'Select',
        label: 'ok',
        probeUrl: 'https://127.0.0.1:${server.port}',
      ),
      const TikNetPersonalProxyNode(
        tag: 'bad',
        groupTag: 'Select',
        label: 'bad',
        probeUrl: 'https://127.0.0.1:1',
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

  test('sortNodesByPing ranks TCP estimates below real measurements', () {
    const nodes = [
      TikNetPersonalProxyNode(tag: 'estimated', groupTag: 'select', label: 'estimated'),
      TikNetPersonalProxyNode(tag: 'measured', groupTag: 'select', label: 'measured'),
    ];
    final pings = {
      // Only the hop to the server — always looks fastest, often does not work.
      'estimated': const TikNetClientPingResult(
        state: TikNetClientPingState.reachable,
        pingMs: 50,
        approximate: true,
      ),
      'measured': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 260),
    };
    final sorted = sortNodesByPing(nodes, pings);
    expect(sorted.map((n) => n.tag).toList(), ['measured', 'estimated']);
  });

  test('urlTestDelaysSettled requires non-zero delays for all wanted tags', () {
    expect(urlTestDelaysSettled({}, {'a'}), isFalse);
    expect(urlTestDelaysSettled({'a': 0}, {'a'}), isFalse);
    expect(urlTestDelaysSettled({'a': 120}, {'a'}), isTrue);
    expect(urlTestDelaysSettled({'a': 120, 'b': 0}, {'a', 'b'}), isFalse);
    expect(urlTestDelaysSettled({'a': 120, 'b': 65000}, {'a', 'b'}), isTrue);
    // Missing tags are not settled yet.
    expect(urlTestDelaysSettled({'a': 50}, {'a', 'missing'}), isFalse);
    // Tags outside the tested group membership are ignored.
    expect(
      urlTestDelaysSettled({'a': 50}, {'a', 'reality-missing'}, members: {'a'}),
      isTrue,
    );
  });

  test('delayByTagFromGroups prefers success over zero/fail', () {
    final groups = [
      OutboundGroup(
        tag: 'Select',
        items: [
          OutboundInfo(tag: 'n1', urlTestDelay: 0),
          OutboundInfo(tag: 'n2', urlTestDelay: 65000),
        ],
      ),
      OutboundGroup(
        tag: 'auto',
        items: [
          OutboundInfo(tag: 'n1', urlTestDelay: 85),
          OutboundInfo(tag: 'n2', urlTestDelay: 40),
        ],
      ),
    ];
    final delays = delayByTagFromGroups(groups);
    expect(delays['n1'], 85);
    expect(delays['n2'], 40);
  });

  test('delaysToPingResults maps 0/missing to noTarget and 65000 to unreachable', () {
    const nodes = [
      TikNetPersonalProxyNode(tag: 'ok', groupTag: 'Select', label: 'ok'),
      TikNetPersonalProxyNode(tag: 'zero', groupTag: 'Select', label: 'zero'),
      TikNetPersonalProxyNode(tag: 'fail', groupTag: 'Select', label: 'fail'),
      TikNetPersonalProxyNode(tag: 'gone', groupTag: 'Select', label: 'gone'),
    ];
    final results = delaysToPingResults(
      {'ok': 42, 'zero': 0, 'fail': 65000},
      nodes,
    );
    expect(results['ok']?.state, TikNetClientPingState.reachable);
    expect(results['ok']?.pingMs, 42);
    expect(results['zero']?.state, TikNetClientPingState.noTarget);
    expect(results['fail']?.state, TikNetClientPingState.unreachable);
    expect(results['gone']?.state, TikNetClientPingState.noTarget);
  });

  test('enrichUrlTestFailsWithTcp upgrades Reality false-قطع when TCP works', () async {
    const nodes = [
      TikNetPersonalProxyNode(
        tag: 'reality',
        groupTag: 'Select',
        label: 'reality',
        probeUrl: 'https://31.216.62.129:2086',
      ),
      TikNetPersonalProxyNode(
        tag: 'dead',
        groupTag: 'Select',
        label: 'dead',
        probeUrl: 'https://127.0.0.1:1',
      ),
      const TikNetPersonalProxyNode(
        tag: 'noprobe',
        groupTag: 'Select',
        label: 'noprobe',
        probeUrl: '',
      ),
    ];
    final before = {
      'reality': const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
      'dead': const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
      'noprobe': const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
    };
    final after = await enrichUrlTestFailsWithTcp(
      before,
      nodes,
      tcpMeasure: (list, {timeout = const Duration(seconds: 3), concurrency = 6}) async {
        return {
          for (final n in list)
            n.tag: switch (n.tag) {
              'reality' => const TikNetClientPingResult(
                state: TikNetClientPingState.reachable,
                pingMs: 55,
              ),
              'noprobe' => const TikNetClientPingResult(state: TikNetClientPingState.noTarget),
              _ => const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
            },
        };
      },
    );
    expect(after['reality']?.state, TikNetClientPingState.reachable);
    expect(after['reality']?.pingMs, 55);
    expect(after['dead']?.state, TikNetClientPingState.unreachable);
    expect(after['noprobe']?.state, TikNetClientPingState.noTarget);
  });

  test('approximate TCP latency is labelled with a tilde', () {
    const exact = TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 132);
    const tcp = TikNetClientPingResult(
      state: TikNetClientPingState.reachable,
      pingMs: 50,
      approximate: true,
    );
    expect(exact.pingLabel, '132 ms');
    expect(tcp.pingLabel, '~50 ms');
  });
}
