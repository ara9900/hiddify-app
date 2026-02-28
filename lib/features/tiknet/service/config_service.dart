import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String configJsonUrl = 'https://ara9900.github.io/app-config/config.json';
const String cacheKeyPanelUrls = 'tiknet_config_panel_urls';
const Duration fetchTimeout = Duration(seconds: 8);
const Duration healthCheckTimeout = Duration(seconds: 5);

/// Hardcoded fallback when config fetch and cache both fail.
const List<String> hardcodedPanelUrls = [
  'https://login.tikn.ir',
];

final configServiceProvider = Provider<ConfigService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return ConfigService(prefs);
});

class ConfigService {
  ConfigService(this._prefs);
  final SharedPreferences _prefs;

  List<String> _parseUrls(Map<String, dynamic>? json) {
    if (json == null) return [];
    final urls = json['api_urls'];
    if (urls is! List) return [];
    return urls
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _getCachedUrls() {
    final raw = _prefs.getString(cacheKeyPanelUrls);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      return list?.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  void _saveToCache(List<String> urls) {
    if (urls.isEmpty) return;
    _prefs.setString(cacheKeyPanelUrls, jsonEncode(urls));
  }

  /// Fetches config from [configJsonUrl], caches [api_urls]. On failure uses cache then [hardcodedPanelUrls].
  Future<List<String>> getPanelUrls() async {
    try {
      final dio = Dio(BaseOptions(connectTimeout: fetchTimeout, receiveTimeout: fetchTimeout));
      final res = await dio.get<Map<String, dynamic>>(configJsonUrl);
      final urls = _parseUrls(res.data);
      if (urls.isNotEmpty) {
        _saveToCache(urls);
        return urls;
      }
    } catch (_) {}
    final cached = _getCachedUrls();
    if (cached.isNotEmpty) return cached;
    return List.from(hardcodedPanelUrls);
  }

  /// Returns the first URL that responds (e.g. GET /api/health). Tries in order: fetched list, cache, hardcoded.
  Future<String> getFirstWorkingPanelUrl() async {
    final urls = await getPanelUrls();
    if (urls.isEmpty) return hardcodedPanelUrls.first;

    final dio = Dio(BaseOptions(connectTimeout: healthCheckTimeout, receiveTimeout: healthCheckTimeout));
    for (final base in urls) {
      final url = base.endsWith('/') ? base : '$base/';
      try {
        final r = await dio.get<String>('${url}api/health');
        if (r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 400) {
          return url.replaceAll(RegExp(r'/$'), '');
        }
      } catch (_) {}
    }
    return urls.first;
  }
}
