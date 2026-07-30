import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/service/tiknet_subscription_sanitizer.dart';

const _realNode =
    'vless://f84f6c60-bfc7-490a-95b1-baf4372e8a45@31.216.62.129:2086?encryption=none&security=reality&sni=shield.nvidia.asia&fp=chrome&type=tcp#vless-alireza';
const _secondNode = 'trojan://pass@de1.example.com:443?security=tls&sni=de1.example.com#Germany-1';

String _b64(String value) => base64Encode(utf8.encode(value));

void main() {
  group('sanitizeSubscriptionPayload', () {
    test('drops unroutable banner entries and keeps servers', () {
      final raw = [
        'vless://uuid@0.0.0.0:1234?encryption=none&type=tcp#${Uri.encodeComponent('ترافیک باقی مانده: ∞')}',
        _realNode,
        'vless://uuid@0.0.0.0:1234?encryption=none&type=tcp#${Uri.encodeComponent('زمان باقی مانده: 14 روز')}',
        _secondNode,
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isTrue);
      expect(result.droppedLabels, hasLength(2));
      expect(const LineSplitter().convert(result.payload), [_realNode, _secondNode]);
    });

    test('drops info entries by name even on a routable host', () {
      final raw = [
        'vless://uuid@de1.example.com:443?encryption=none&type=tcp#${Uri.encodeComponent('TikNet | Traffic: 12GB')}',
        _realNode,
      ].join('\n');

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.droppedLabels, ['TikNet | Traffic: 12GB']);
      expect(result.payload, _realNode);
    });

    test('keeps base64 payloads base64 encoded', () {
      final raw = _b64([
        'vless://uuid@0.0.0.0:1234?encryption=none&type=tcp#${Uri.encodeComponent('حجم مصرفی: 3GB')}',
        _realNode,
      ].join('\n'));

      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isTrue);
      expect(utf8.decode(base64Decode(result.payload)), _realNode);
    });

    test('handles unpadded base64 subscriptions', () {
      final padded = _b64('$_realNode\n$_secondNode\nvless://uuid@0.0.0.0:1234#${Uri.encodeComponent('منقضی')}');
      final result = sanitizeSubscriptionPayload(padded.replaceAll('=', ''));

      expect(result.changed, isTrue);
      expect(utf8.decode(base64Decode(result.payload)), '$_realNode\n$_secondNode');
    });

    test('drops vmess banners parsed from their base64 body', () {
      final banner = 'vmess://${_b64(jsonEncode({
            'v': '2',
            'ps': 'روز مانده: 9',
            'add': '0.0.0.0',
            'port': '1234',
            'id': 'uuid',
          }))}';
      final result = sanitizeSubscriptionPayload('$banner\n$_realNode');

      expect(result.droppedLabels, ['روز مانده: 9']);
      expect(result.payload, _realNode);
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

    test('keeps a normal subscription byte-identical', () {
      final raw = '$_realNode\n$_secondNode';
      final result = sanitizeSubscriptionPayload(raw);

      expect(result.changed, isFalse);
      expect(result.payload, raw);
    });
  });
}
