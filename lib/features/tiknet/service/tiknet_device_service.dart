import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Persistent device id + panel register heartbeat (self-hosted, no FCM).
class TikNetDeviceService {
  TikNetDeviceService(this._ref);
  final Ref _ref;

  Future<String> getOrCreateDeviceId() async {
    var id = _ref.read(Preferences.tikNetDeviceId);
    if (id.isEmpty) {
      id = const Uuid().v4();
      await _ref.read(Preferences.tikNetDeviceId.notifier).update(id);
    }
    return id;
  }

  Future<void> registerIfLoggedIn() async {
    try {
      final auth = _ref.read(authServiceProvider);
      if (!auth.hasAppSession()) return;

      final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
      final token = auth.getToken();
      if (baseUrl.isEmpty || token.isEmpty) return;

      final deviceId = await getOrCreateDeviceId();
      final appInfo = await _ref.read(appInfoProvider.future);
      await _ref.read(tikNetApiProvider).registerDevice(
            baseUrl: baseUrl,
            accessToken: token,
            deviceId: deviceId,
            platform: Platform.isAndroid ? 'android' : appInfo.operatingSystem,
            appVersion: appInfo.version,
            versionCode: int.tryParse(appInfo.buildNumber),
          );
    } catch (_) {
      // must not affect login/VPN
    }
  }
}

final tikNetDeviceServiceProvider = Provider<TikNetDeviceService>(
  (ref) => TikNetDeviceService(ref),
);
