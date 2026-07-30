import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/service/tiknet_subscription_sanitizer.dart';

const _realityNode =
    'vless://f84f6c60-bfc7-490a-95b1-baf4372e8a45@31.216.62.129:2086?encryption=none&security=reality&sni=shield.nvidia.asia&fp=chrome&type=tcp#vless-alireza';
const _wsNode =
    'vless://f84f6c60-bfc7-490a-95b1-baf4372e8a45@stream1.2loopi.ir:8080?encryption=none&security=none&type=ws#Germany-1';
const _secondNode = 'trojan://pass@de1.example.com:443?security=tls&sni=de1.example.com#Germany-1';

String _b64(String value) => base64Encode(utf8.encode(value));

bool _hasCoreXray(String link) {
  final uri = Uri.parse(link);
  return (uri.queryParameters['core'] ?? '').toLowerCase() == 'xray';
}

void main() {
  group('sanitizeSubscriptionPayload', () {
    test('drops unroutable banner entries and keeps servers', () {
      final raw = [
        'vless://uuid@0.0.0.0:1234?encryption=none&type=tcp#${Uri.encodeComponent('ترافیک باقی مانده: ∞')}',
        _wsNode,
        'vless://uuid@0.0.0.0:1234?encryption=none&type=tcp#${Uri.encodeComponent('زمان باقی مانده: 14 روز')}',
        _secondNode,
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isTrue);
      expect(result.droppedLabels, hasLength(2));
      expect(const LineSplitter().convert(result.payload), [_wsNode, _secondNode]);
    });

    test('drops info entries by name even on a routable host', () {
      final raw = [
        'vless://uuid@de1.example.com:443?encryption=none&type=tcp#${Uri.encodeComponent('TikNet | Traffic: 12GB')}',
        _wsNode,
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.droppedLabels, ['TikNet | Traffic: 12GB']);
      expect(result.payload, _wsNode);
    });

    test('keeps base64 payloads base64 encoded', () {
      final raw = _b64([
        'vless://uuid@0.0.0.0:1234?encryption=none&type=tcp#${Uri.encodeComponent('حجم مصرفی: 3GB')}',
        _wsNode,
      ].join('\n'));

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isTrue);
      expect(utf8.decode(base64Decode(result.payload)), _wsNode);
    });

    test('handles unpadded base64 subscriptions', () {
      final padded = _b64('$_wsNode\n$_secondNode\nvless://uuid@0.0.0.0:1234#${Uri.encodeComponent('منقضی')}');
      final result = sanitizeSubscriptionPayload(padded.replaceAll('=', ''));

      expect(result.changed, isTrue);
      expect(utf8.decode(base64Decode(result.payload)), '$_wsNode\n$_secondNode');
    });

    test('drops vmess banners parsed from their base64 body', () {
      final banner = 'vmess://${_b64(jsonEncode({
            'v': '2',
            'ps': 'روز مانده: 9',
            'add': '0.0.0.0',
            'port': '1234',
            'id': 'uuid',
          }))}';
      final result = sanitizeSubscriptionPayload('$banner\n$_wsNode');

      expect(result.droppedLabels, ['روز مانده: 9']);
      expect(result.payload, _wsNode);
    });

    test('leaves sing-box json untouched', () {
      const raw = '{"outbounds":[{"type":"vless","tag":"a","server":"0.0.0.0"}]}';
      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isFalse);
      expect(result.payload, raw);
    });

    test('returns the original payload when every entry looks like a banner', () {
      final raw = [
        'vless://uuid@0.0.0.0:1234#${Uri.encodeComponent('ترافیک باقی مانده')}',
        'vless://uuid@0.0.0.0:1234#${Uri.encodeComponent('منقضی')}',
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isFalse);
      expect(result.payload, raw);
    });

    test('forces Reality links through the Xray converter', () {
      final raw = [
        'vless://uuid@31.216.62.129:2086?encryption=none&security=reality&sni=shield.nvidia.asia&fp=chrome&pbk=pk&sid=c2e6&spx=%2Fpath&type=tcp#reality',
        _secondNode,
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);
      final lines = const LineSplitter().convert(result.payload);

      expect(result.forcedXrayCount, 1);
      expect(_hasCoreXray(lines.first), isTrue);
      expect(lines.first, contains('security=reality'));
      expect(lines.last, _secondNode);
    });

    test('also stamps core=xray when dropping info banners around a Reality node', () {
      final raw = [
        'vless://uuid@0.0.0.0:1234#${Uri.encodeComponent('ترافیک باقی مانده')}',
        _realityNode,
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);
      final kept = const LineSplitter().convert(result.payload).single;

      expect(result.droppedLabels, hasLength(1));
      expect(result.forcedXrayCount, 1);
      expect(_hasCoreXray(kept), isTrue);
    });

    test('keeps a normal non-Reality subscription byte-identical', () {
      final raw = '$_wsNode\n$_secondNode';
      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isFalse);
      expect(result.payload, raw);
    });
  });
}
