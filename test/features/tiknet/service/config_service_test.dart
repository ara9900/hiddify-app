import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/service/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ConfigService', () {
    late SharedPreferences prefs;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
    });

    setUp(() async {
      prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    test('getPanelUrls returns URLs from GitHub Pages when it responds', () async {
      final configJson = jsonEncode({'api_urls': ['https://panel.from-github.test', 'https://backup.test']});
      final adapter = _MockAdapter(
        onConfig: () => configJson,
        onHealth: () => 'ok',
      );
      final service = ConfigService(prefs, httpClientAdapter: adapter);

      final urls = await service.getPanelUrls();

      expect(urls, ['https://panel.from-github.test', 'https://backup.test']);
      expect(prefs.getString(cacheKeyPanelUrls), configJson);
    });

    test('getPanelUrls returns cached URLs when GitHub Pages does not respond', () async {
      final cachedUrls = ['https://cached.panel.test'];
      await prefs.setString(cacheKeyPanelUrls, jsonEncode(cachedUrls));
      final adapter = _MockAdapter(onConfig: () => throw Exception('network error'));
      final service = ConfigService(prefs, httpClientAdapter: adapter);

      final urls = await service.getPanelUrls();

      expect(urls, cachedUrls);
    });

    test('getPanelUrls returns hardcoded URLs when GitHub and cache both fail', () async {
      final adapter = _MockAdapter(onConfig: () => throw Exception('network error'));
      final service = ConfigService(prefs, httpClientAdapter: adapter);

      final urls = await service.getPanelUrls();

      expect(urls, hardcodedPanelUrls);
      expect(urls.isNotEmpty, true);
      expect(urls.first, 'https://login.tikn.ir');
    });

    test('getFirstWorkingPanelUrl returns first URL when GitHub responds and health succeeds', () async {
      final configJson = jsonEncode({'api_urls': ['https://first.test', 'https://second.test']});
      final adapter = _MockAdapter(
        onConfig: () => configJson,
        onHealth: () => 'ok',
      );
      final service = ConfigService(prefs, httpClientAdapter: adapter);

      final url = await service.getFirstWorkingPanelUrl();

      expect(url, 'https://first.test');
    });

    test('getFirstWorkingPanelUrl falls back to first in list when no health responds (cache then hardcoded)', () async {
      await prefs.setString(cacheKeyPanelUrls, jsonEncode(['https://cached.only.test']));
      final adapter = _MockAdapter(
        onConfig: () => throw Exception('offline'),
        onHealth: () => throw Exception('unreachable'),
      );
      final service = ConfigService(prefs, httpClientAdapter: adapter);

      final url = await service.getFirstWorkingPanelUrl();

      expect(url, 'https://cached.only.test');
    });
  });
}

/// Mock [HttpClientAdapter] that returns config JSON for config URL and body for health URL.
class _MockAdapter extends HttpClientAdapter {
  _MockAdapter({
    String? Function()? onConfig,
    String? Function()? onHealth,
  })  : _onConfig = onConfig,
        _onHealth = onHealth;

  final String? Function()? _onConfig;
  final String? Function()? _onHealth;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri.toString();
    if (uri == configJsonUrl) {
      final body = _onConfig?.call();
      if (body != null) {
        return ResponseBody.fromString(body, 200, headers: {'content-type': 'application/json'});
      }
      throw Exception('config unreachable');
    }
    if (uri.contains('api/health')) {
      final body = _onHealth?.call();
      if (body != null) {
        return ResponseBody.fromString(body, 200);
      }
      throw Exception('health unreachable');
    }
    throw Exception('unknown request: $uri');
  }
}
