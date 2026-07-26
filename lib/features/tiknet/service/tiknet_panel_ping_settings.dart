import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/tiknet/model/tiknet_brand.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/utils/validators.dart';

/// Default urltest probe used when panel does not send a URL.
const kTikNetDefaultPingTestUrl = ConfigOptions.tikNetDefaultConnectionTestUrl;

/// Built-in candidates (panel can ship the same list + custom URLs).
const kTikNetRecommendedPingTestUrls = <String>[
  'https://www.gstatic.com/generate_204',
  'http://www.gstatic.com/generate_204',
  'http://connectivitycheck.gstatic.com/generate_204',
  'https://www.google.com/generate_204',
  'http://cp.cloudflare.com/',
  'https://cp.cloudflare.com/',
  'http://detectportal.firefox.com/success.txt',
  'http://captive.apple.com/hotspot-detect.html',
  'https://1.1.1.1/',
  'http://1.1.1.1/',
];

String? _validUrl(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return isUrl(trimmed) ? trimmed : null;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final v = _validUrl(json[key] is String ? json[key] as String : null);
    if (v != null) return v;
  }
  return null;
}

List<String> parsePingTestUrlChoices(Map<String, dynamic>? json) {
  if (json == null) return const [];
  final out = <String>[];
  void addAll(dynamic raw) {
    if (raw is! List) return;
    for (final item in raw) {
      if (item is String) {
        final u = _validUrl(item);
        if (u != null && !out.contains(u)) out.add(u);
      } else if (item is Map) {
        final u = _validUrl(
          (item['url'] ?? item['value'] ?? item['ping_test_url'])?.toString(),
        );
        if (u != null && !out.contains(u)) out.add(u);
      }
    }
  }

  addAll(json['ping_test_urls']);
  addAll(json['connection_test_urls']);
  addAll(json['url_test_urls']);
  final network = json['network'];
  if (network is Map) {
    addAll(network['ping_test_urls']);
    addAll(network['connection_test_urls']);
  }
  return out;
}

/// Reads panel-controlled HTTP urltest URL (same as Hiddify «URL تست اتصال»).
String? parsePingTestUrl(Map<String, dynamic>? json) {
  if (json == null) return null;

  final direct = _firstString(json, const [
    'ping_test_url',
    'connection_test_url',
    'url_test_url',
    'connection-test-url',
  ]);
  if (direct != null) return direct;

  final network = json['network'];
  if (network is Map) {
    final nested = _firstString(Map<String, dynamic>.from(network), const [
      'ping_test_url',
      'connection_test_url',
      'url_test_url',
      'connection-test-url',
    ]);
    if (nested != null) return nested;
  }

  final choices = parsePingTestUrlChoices(json);
  if (choices.isNotEmpty) return choices.first;
  return null;
}

/// Applies [url] to [ConfigOptions.connectionTestUrl] when valid (HTTP urltest, not TCP).
Future<bool> applyPanelPingTestUrl(dynamic ref, String? url) async {
  final trimmed = _validUrl(url);
  if (trimmed == null) return false;
  final current = ref.read(ConfigOptions.connectionTestUrl);
  if (current == trimmed) return false;
  await ref.read(ConfigOptions.connectionTestUrl.notifier).update(trimmed);
  TikNetDiagnosticLog.i('ping', 'panel ping_test_url applied', {'url': trimmed});
  return true;
}

Future<void> applyPanelPingSettingsFromAppConfig(dynamic ref, Map<String, dynamic> appConfig) async {
  final selected = parsePingTestUrl(appConfig);
  final applied = await applyPanelPingTestUrl(ref, selected);
  if (!applied && selected == null) {
    final choices = parsePingTestUrlChoices(appConfig);
    TikNetDiagnosticLog.i('ping', 'panel ping settings', {
      'selected': ref.read(ConfigOptions.connectionTestUrl),
      'choices': choices.length,
    });
  }
}

Future<void> applyPanelPingSettingsFromBrand(dynamic ref, TikNetBrand? brand) async {
  if (brand == null) return;
  await applyPanelPingTestUrl(ref, brand.pingTestUrl);
}
