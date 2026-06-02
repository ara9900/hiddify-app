import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/tiknet/service/tiknet_user_info_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Best-effort anonymous telemetry to panel POST /api/customer/telemetry.
class TikNetTelemetryService {
  TikNetTelemetryService(this._ref);
  final Ref _ref;

  static const _events = {
    'connect_success',
    'connect_fail',
    'app_open',
    'update_dismissed',
    'vpn_core_start_failed',
    'connection_error',
    'user_report',
  };
  static bool _appOpenSent = false;

  Future<void> sendAppOpenOnce() async {
    if (_appOpenSent) return;
    _appOpenSent = true;
    await send('app_open');
  }

  Future<void> reportConnectionError(ConnectionFailure failure, {String? stage}) async {
    final t = await _ref.read(translationsProvider.future);
    final presented = failure.present(t);
    await send(
      'connection_error',
      payload: {
        'failure_type': failure.runtimeType.toString(),
        'title': presented.type,
        'message': presented.message ?? failure.toString(),
        if (stage != null) 'stage': stage,
        ..._contextPayload(),
      },
    );
  }

  Future<void> reportVpnCoreStartFailed({required String message, int? attempt}) async {
    await send(
      'vpn_core_start_failed',
      payload: {
        'message': message,
        if (attempt != null) 'attempt': attempt,
        ..._contextPayload(),
      },
    );
  }

  Future<void> reportUserIssue({required String message, String? context}) async {
    await send(
      'user_report',
      payload: {
        'message': message,
        if (context != null) 'context': context,
        ..._contextPayload(),
      },
    );
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
        'device_model': _deviceModel(),
        if (Platform.isAndroid) 'android_sdk': _androidSdk(),
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

  Map<String, dynamic> _contextPayload() {
    final info = _ref.read(tikNetUserInfoProvider);
    return {
      if (info != null) 'username': info.username,
      if (info?.planName != null) 'plan': info!.planName,
    };
  }

  String _deviceModel() {
    if (Platform.isAndroid) {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
    }
    return Platform.operatingSystem;
  }

  int? _androidSdk() {
    if (!Platform.isAndroid) return null;
    final match = RegExp(r'API (\d+)').firstMatch(Platform.operatingSystemVersion);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}

final tikNetTelemetryServiceProvider = Provider<TikNetTelemetryService>(
  (ref) => TikNetTelemetryService(ref),
);
