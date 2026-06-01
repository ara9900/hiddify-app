import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Best-effort anonymous telemetry to panel POST /api/customer/telemetry.
class TikNetTelemetryService {
  TikNetTelemetryService(this._ref);
  final Ref _ref;

  static const _events = {'connect_success', 'connect_fail', 'app_open', 'update_dismissed'};
  static bool _appOpenSent = false;

  Future<void> sendAppOpenOnce() async {
    if (_appOpenSent) return;
    _appOpenSent = true;
    await send('app_open');
  }

  Future<void> send(String event, {Map<String, dynamic>? payload}) async {
    if (!_events.contains(event)) return;
    final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    if (baseUrl.isEmpty) return;

    try {
      final appInfo = await _ref.read(appInfoProvider.future);
      final body = <String, dynamic>{
        'event': event,
        'app_version': appInfo.version,
        'version_code': int.tryParse(appInfo.buildNumber) ?? 0,
        'platform': Platform.isAndroid ? 'android' : appInfo.operatingSystem,
        'payload': payload ?? {},
      };

      final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))).post<void>(
        '${root}api/customer/telemetry',
        data: body,
      );
    } catch (_) {
      // telemetry must never affect UX
    }
  }
}

final tikNetTelemetryServiceProvider = Provider<TikNetTelemetryService>(
  (ref) => TikNetTelemetryService(ref),
);
