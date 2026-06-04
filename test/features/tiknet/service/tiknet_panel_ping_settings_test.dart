import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/tiknet_brand.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_ping_settings.dart';

void main() {
  group('parsePingTestUrl', () {
    test('reads top-level ping_test_url', () {
      expect(
        parsePingTestUrl({'ping_test_url': 'https://cp.cloudflare.com'}),
        'https://cp.cloudflare.com',
      );
    });

    test('reads nested network.ping_test_url', () {
      expect(
        parsePingTestUrl({
          'network': {'ping_test_url': 'http://captive.apple.com/hotspot-detect.html'},
        }),
        'http://captive.apple.com/hotspot-detect.html',
      );
    });

    test('returns null for invalid or missing', () {
      expect(parsePingTestUrl(null), isNull);
      expect(parsePingTestUrl({'ping_test_url': ''}), isNull);
      expect(parsePingTestUrl({'ping_test_url': 'not-a-url'}), isNull);
    });
  });

  group('TikNetBrand', () {
    test('parses ping_test_url from brand json', () {
      final brand = TikNetBrand.fromJson({
        'name': 'Test',
        'ping_test_url': 'https://www.gstatic.com/generate_204',
      });
      expect(brand.pingTestUrl, 'https://www.gstatic.com/generate_204');
    });
  });
}
