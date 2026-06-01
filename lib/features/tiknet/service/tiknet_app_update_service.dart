import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/tiknet_app_update_info.dart';
import 'package:hiddify/features/tiknet/service/config_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const Duration _updateCheckTimeout = Duration(seconds: 12);

/// Fetches app-update policy from panel (and optional GitHub config fallback).
class TikNetAppUpdateService {
  TikNetAppUpdateService(this._ref);
  final Ref _ref;

  Future<TikNetAppUpdateInfo> fetchUpdateInfo() async {
    final panelUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    if (panelUrl.isNotEmpty) {
      final fromPanel = await _fetchFromBase(panelUrl);
      if (fromPanel != null && fromPanel.enabled) return fromPanel;
    }

    final configUrls = await _ref.read(configServiceProvider).getPanelUrls();
    for (final url in configUrls) {
      if (url == panelUrl) continue;
      final info = await _fetchFromBase(url);
      if (info != null && info.enabled) return info;
    }

    final github = await _fetchFromGitHubConfig();
    if (github != null && github.enabled) return github;

    return TikNetAppUpdateInfo.disabled();
  }

  Future<TikNetAppUpdateInfo?> _fetchFromBase(String baseUrl) async {
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _updateCheckTimeout,
        receiveTimeout: _updateCheckTimeout,
      ));
      final res = await dio.get<Map<String, dynamic>>(
        '${root}api/customer/app-update',
        queryParameters: {'channel': _ref.read(Preferences.tikNetUpdateChannel)},
      );
      return TikNetAppUpdateInfo.fromJson(res.data) ?? TikNetAppUpdateInfo.disabled();
    } catch (_) {
      return null;
    }
  }

  Future<TikNetAppUpdateInfo?> _fetchFromGitHubConfig() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _updateCheckTimeout,
        receiveTimeout: _updateCheckTimeout,
      ));
      final res = await dio.get<Map<String, dynamic>>(configJsonUrl);
      final data = res.data;
      if (data == null) return null;
      final block = data['app_update'];
      if (block is Map<String, dynamic>) {
        return TikNetAppUpdateInfo.fromJson({'update': block});
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> downloadApk(
    TikNetAppUpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'tiknet-update-${info.versionCode}.apk';
    final path = p.join(dir.path, fileName);

    final dio = Dio();
    await dio.download(
      info.apkUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('فایل APK دریافت نشد');
    }

    if (info.sha256.isNotEmpty) {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest != info.sha256) {
        await file.delete();
        throw Exception('بررسی امنیتی فایل ناموفق بود');
      }
    }

    return path;
  }
}

final tikNetAppUpdateServiceProvider = Provider<TikNetAppUpdateService>(
  (ref) => TikNetAppUpdateService(ref),
);
