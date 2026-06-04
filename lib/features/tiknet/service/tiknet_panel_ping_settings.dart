import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/tiknet/model/tiknet_brand.dart';
import 'package:hiddify/utils/validators.dart';

/// Reads panel-controlled HTTP urltest URL (same as Hiddify «URL تست اتصال»).
String? parsePingTestUrl(Map<String, dynamic>? json) {
  if (json == null) return null;
  final direct = (json['ping_test_url'] as String?)?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final network = json['network'];
  if (network is Map) {
    final nested = (network['ping_test_url'] as String?)?.trim();
    if (nested != null && nested.isNotEmpty) return nested;
  }
  return null;
}

/// Applies [url] to [ConfigOptions.connectionTestUrl] when valid (HTTP urltest, not TCP).
Future<bool> applyPanelPingTestUrl(dynamic ref, String? url) async {
  final trimmed = url?.trim();
  if (trimmed == null || trimmed.isEmpty || !isUrl(trimmed)) return false;
  final current = ref.read(ConfigOptions.connectionTestUrl);
  if (current == trimmed) return false;
  await ref.read(ConfigOptions.connectionTestUrl.notifier).update(trimmed);
  return true;
}

Future<void> applyPanelPingSettingsFromAppConfig(dynamic ref, Map<String, dynamic> appConfig) async {
  await applyPanelPingTestUrl(ref, parsePingTestUrl(appConfig));
}

Future<void> applyPanelPingSettingsFromBrand(dynamic ref, TikNetBrand? brand) async {
  if (brand == null) return;
  await applyPanelPingTestUrl(ref, brand.pingTestUrl);
}
