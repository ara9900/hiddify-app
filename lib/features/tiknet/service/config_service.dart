import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub Pages config (may be filtered in some regions).
const String configJsonUrl = 'https://ara9900.github.io/app-config/config.json';

/// Fallback config on panel domain (same JSON: { "api_urls": [...] }).
const String panelConfigJsonUrl = 'https://panel.tikn.ir/config.json';

/// Ordered config sources: GitHub → panel domain → cache → hardcoded.
const List<String> configJsonUrls = [configJsonUrl, panelConfigJsonUrl];

const String cacheKeyPanelUrls = 'tiknet_config_panel_urls';
const Duration fetchTimeout = Duration(seconds: 8);
const Duration healthCheckTimeout = Duration(seconds: 5);

/// Hardcoded fallback when all remote config fetches and cache fail.
const List<String> hardcodedPanelUrls = [
  'https://panel.tikn.ir',
];

final configServiceProvider = Provider<ConfigService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return ConfigService(prefs);
});

class ConfigService {
  ConfigService(this._prefs, {HttpClientAdapter? httpClientAdapter})
      : _httpClientAdapter = httpClientAdapter;

  final SharedPreferences _prefs;
  final HttpClientAdapter? _httpClientAdapter;

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

  Dio _configDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: fetchTimeout,
      sendTimeout: fetchTimeout,
      receiveTimeout: fetchTimeout,
    ));
    if (_httpClientAdapter != null) dio.httpClientAdapter = _httpClientAdapter!;
    return dio;
  }

  Future<List<String>?> _fetchUrlsFrom(String url) async {
    try {
      final res = await _configDio().get<Map<String, dynamic>>(url);
      final urls = _parseUrls(res.data);
      if (urls.isNotEmpty) return urls;
    } catch (_) {}
    return null;
  }

  /// Fetches [api_urls]: GitHub → panel.tikn.ir/config.json → cache → [hardcodedPanelUrls].
  Future<List<String>> getPanelUrls() async {
    for (final url in configJsonUrls) {
      final urls = await _fetchUrlsFrom(url);
      if (urls != null) {
        _saveToCache(urls);
        return urls;
      }
    }
    final cached = _getCachedUrls();
    if (cached.isNotEmpty) return cached;
    return List.from(hardcodedPanelUrls);
  }

  /// Returns the first URL that responds (GET /api/health). Falls back to first in list.
  Future<String> getFirstWorkingPanelUrl() async {
    final urls = await getPanelUrls();
    if (urls.isEmpty) return hardcodedPanelUrls.first;

    final dio = Dio(BaseOptions(
      connectTimeout: healthCheckTimeout,
      sendTimeout: healthCheckTimeout,
      receiveTimeout: healthCheckTimeout,
    ));
    if (_httpClientAdapter != null) dio.httpClientAdapter = _httpClientAdapter!;
    for (final base in urls) {
      final url = base.endsWith('/') ? base : '$base/';
      try {
        final r = await dio.get<String>('${url}api/health');
        if (r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 400) {
          return url.replaceAll(RegExp(r'/$'), '');
        }
      } catch (_) {
        // Skip this URL, try next (no crash on unreachable host / no internet).
      }
    }
    return urls.first;
  }
}
