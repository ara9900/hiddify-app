import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';

void main() {
  test('parsePersonalOutboundsFromConfig resolves urltest outbound refs (Hiddify merged)', () {
    const raw = '''
{
  "route": {"final": "proxy"},
  "outbounds": [
    {"type": "selector", "tag": "proxy", "outbounds": ["auto"]},
    {"type": "urltest", "tag": "auto", "outbounds": ["DE-1", "TR-2"]},
    {"type": "vless", "tag": "DE-1", "server": "de.example.com"},
    {"type": "vless", "tag": "TR-2", "server": "tr.example.com"}
  ]
}
''';
    final catalog = parsePersonalOutboundsFromConfig(raw);
    expect(catalog, isNotNull);
    expect(catalog!.autoModes.length, 1);
    expect(catalog.nodes.length, 2);
    expect(catalog.nodes.map((n) => n.tag).toList(), containsAll(['DE-1', 'TR-2']));
  });

  test('parsePersonalOutboundsFromConfig supports Xray protocol field', () {
    const raw = '''
{
  "outbounds": [
    {"protocol": "vless", "tag": "DE", "settings": {"vnext": [{"address": "de.example.com"}]}},
    {"protocol": "vless", "tag": "TR", "settings": {"vnext": [{"address": "tr.example.com"}]}}
  ]
}
''';
    final catalog = parsePersonalOutboundsFromConfig(raw);
    expect(catalog, isNotNull);
    expect(catalog!.nodes.length, 2);
  });

  test('shouldFetchSubscriptionOnDevice when panel bytes have no nodes but URL is http', () {
    expect(shouldFetchSubscriptionOnDevice('', 'https://panel.example/sub/uuid/'), isTrue);
    expect(shouldFetchSubscriptionOnDevice('not-json', 'https://panel.example/sub/uuid/'), isTrue);
    const singbox = '''
{"outbounds":[{"type":"vless","tag":"DE","server":"de.example.com"}]}
''';
    expect(shouldFetchSubscriptionOnDevice(singbox, 'https://panel.example/sub/uuid/'), isFalse);
    expect(shouldFetchSubscriptionOnDevice(singbox, ''), isFalse);
  });

  test('normalizeSubscriptionFetchUrl appends singbox for Hiddify user page', () {
    expect(
      normalizeSubscriptionFetchUrl('https://sub.example/12345678-1234-1234-1234-123456789abc/'),
      'https://sub.example/12345678-1234-1234-1234-123456789abc/singbox/',
    );
    expect(
      normalizeSubscriptionFetchUrl('https://sub.example/12345678-1234-1234-1234-123456789abc'),
      'https://sub.example/12345678-1234-1234-1234-123456789abc/singbox/',
    );
    expect(
      normalizeSubscriptionFetchUrl('https://sub.example/uuid/singbox/'),
      'https://sub.example/uuid/singbox/',
    );
  });

  test('shouldFetchSubscriptionOnDevice when panel JSON has no proxy nodes', () {
    const raw = '{"outbounds":[{"type":"selector","tag":"proxy","outbounds":[]}]}';
    expect(shouldFetchSubscriptionOnDevice(raw, 'https://sub.example/uuid/'), isTrue);
  });

  test('normalizeSubscriptionFetchUrl strips Hiddify display fragment', () {
    expect(
      normalizeSubscriptionFetchUrl(
        'https://stream.24insta.ir/PJQ3wwl6yaKoDnc0WZrA/3f904906-66e2-4003-b6f5-26f67254562b/xray/#prs360',
      ),
      'https://stream.24insta.ir/PJQ3wwl6yaKoDnc0WZrA/3f904906-66e2-4003-b6f5-26f67254562b/xray/',
    );
  });

  test('parsePersonalOutboundsFromConfig supports Hiddify xray JSON array bundle', () {
    const raw = '''
[
  {
    "remarks": "traffic info only",
    "outbounds": [
      {"tag": "direct", "protocol": "freedom"},
      {"tag": "block", "protocol": "blackhole"}
    ]
  },
  {
    "remarks": "Germany CDN",
    "outbounds": [
      {"tag": "DE-vless", "protocol": "vless", "settings": {"vnext": [{"address": "de.example.com", "port": 443}]}}
    ]
  },
  {
    "remarks": "Turkey",
    "outbounds": [
      {"tag": "TR-trojan", "protocol": "trojan", "settings": {"servers": [{"address": "tr.example.com", "port": 443}]}}
    ]
  }
]
''';
    final catalog = parsePersonalOutboundsFromConfig(raw);
    expect(catalog, isNotNull);
    expect(catalog!.nodes.length, 2);
    expect(catalog.nodes.map((n) => n.label).toList(), containsAll(['Germany CDN', 'Turkey']));
    expect(catalog.nodes.map((n) => n.tag).toList(), containsAll(['DE-vless', 'TR-trojan']));
  });

  test('parsePersonalOutboundsFromConfig parses real Hiddify xray bundle sample', () {
    const samplePath = r'C:\Users\htock\.cursor\projects\d-hiddify-with-cursor\uploads\xray-0.md';
    final file = File(samplePath);
    if (!file.existsSync()) return;

    final text = file.readAsStringSync();
    final start = text.indexOf('[');
    expect(start, greaterThan(0));
    final catalog = parsePersonalOutboundsFromConfig(text.substring(start));
    expect(catalog, isNotNull);
    expect(catalog!.nodes.length, greaterThan(10));
  });

  test('parsePersonalOutboundsFromSubscriptionLinks reads base64 vless lines', () {
    const link = 'vless://uuid@host:443?security=tls#Germany';
    final b64 = 'dmxlc3M6Ly91dWlkQGhvc3Q6NDQzP3NlY3VyaXR5PXRscyNHZXJtYW55';
    final catalog = parsePersonalOutboundsFromSubscriptionLinks(b64);
    expect(catalog, isNotNull);
    expect(catalog!.nodes.length, 1);
    expect(catalog.nodes.first.label, 'Germany');
  });
}
