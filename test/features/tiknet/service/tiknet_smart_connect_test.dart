import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_smart_connect.dart';

const _nodes = [
  TikNetPersonalProxyNode(tag: 'reality', groupTag: 'select', label: 'Reality'),
  TikNetPersonalProxyNode(tag: 'de-1', groupTag: 'select', label: 'DE 1'),
  TikNetPersonalProxyNode(tag: 'nl-1', groupTag: 'select', label: 'NL 1'),
];

void main() {
  group('pickBestNodeByPing', () {
    test('ignores a TCP-estimated ping when any node has a real measurement', () {
      // The Reality node fails urltest every time; its 50 ms is a raw TCP
      // handshake, so it must not beat a genuinely working 180 ms node.
      final pings = {
        'reality': const TikNetClientPingResult(
          state: TikNetClientPingState.reachable,
          pingMs: 50,
          approximate: true,
        ),
        'de-1': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 180),
        'nl-1': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 240),
      };
      final best = pickBestNodeByPing(_nodes, pings);
      expect(best?.tag, 'de-1');
      expect(best?.approximate, isFalse);
    });

    test('falls back to the best estimate when nothing has a real measurement', () {
      final pings = {
        'reality': const TikNetClientPingResult(
          state: TikNetClientPingState.reachable,
          pingMs: 50,
          approximate: true,
        ),
        'de-1': const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
        'nl-1': const TikNetClientPingResult(state: TikNetClientPingState.noTarget),
      };
      final best = pickBestNodeByPing(_nodes, pings);
      expect(best?.tag, 'reality');
      expect(best?.approximate, isTrue);
    });

    test('returns null when no node is reachable', () {
      final pings = {
        'reality': const TikNetClientPingResult(state: TikNetClientPingState.unreachable),
        'de-1': const TikNetClientPingResult(state: TikNetClientPingState.noTarget),
      };
      expect(pickBestNodeByPing(_nodes, pings), isNull);
    });

    test('skips urltest timeout sentinels', () {
      final pings = {
        'reality': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 65000),
        'de-1': const TikNetClientPingResult(state: TikNetClientPingState.reachable, pingMs: 300),
      };
      expect(pickBestNodeByPing(_nodes, pings)?.tag, 'de-1');
    });
  });
}
