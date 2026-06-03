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

  test('parsePersonalOutboundsFromSubscriptionLinks reads base64 vless lines', () {
    const link = 'vless://uuid@host:443?security=tls#Germany';
    final b64 = 'dmxlc3M6Ly91dWlkQGhvc3Q6NDQzP3NlY3VyaXR5PXRscyNHZXJtYW55';
    final catalog = parsePersonalOutboundsFromSubscriptionLinks(b64);
    expect(catalog, isNotNull);
    expect(catalog!.nodes.length, 1);
    expect(catalog.nodes.first.label, 'Germany');
  });
}
