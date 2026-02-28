import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'auth_service.dart';
import 'tiknet_api.dart';

/// Thrown when sync fails due to 401 (token expired). Caller should redirect to login.
class SyncTokenExpiredException implements Exception {
  @override
  String toString() => 'Token expired';
}

/// Syncs profile and config from panel API and caches in SharedPreferences.
class SyncService {
  SyncService(this._ref);
  final Ref _ref;

  /// Fetches profile (GET /api/customer/me) and config (GET /api/customer/subscription/config),
  /// saves to SharedPreferences. Returns true on success.
  /// On 401: logs out and throws [SyncTokenExpiredException].
  /// On network error: returns false (no logout).
  Future<bool> syncAll() async {
    final auth = _ref.read(authServiceProvider);
    if (!auth.isLoggedIn()) return false;

    final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    final token = auth.getToken();
    if (baseUrl.isEmpty || token.isEmpty) return false;

    final api = _ref.read(tikNetApiProvider);

    try {
      final profile = await api.getMe(baseUrl: baseUrl, accessToken: token);
      final profileJson = _profileToJson(profile);
      await _ref.read(Preferences.tikNetCachedProfile.notifier).update(jsonEncode(profileJson));

      final configBytes = await api.getSubscriptionConfig(baseUrl: baseUrl, accessToken: token);
      final configBase64 = base64Encode(configBytes);
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(configBase64);

      await _ref.read(Preferences.tikNetLastSyncTime.notifier).update(DateTime.now());
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await auth.logout();
        throw SyncTokenExpiredException();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _profileToJson(TikNetUserInfo p) {
    return {
      'username': p.username,
      'full_name': p.fullName,
      'expire_date': p.expireDate?.toIso8601String(),
      'has_subscription': p.hasSubscription,
    };
  }

  /// Returns cached profile from SharedPreferences. Null if empty or invalid.
  TikNetUserInfo? getProfile() {
    final raw = _ref.read(Preferences.tikNetCachedProfile);
    if (raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>?;
      if (map == null) return null;
      return TikNetUserInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Returns cached config content (decoded from stored base64). Empty string if none.
  String getConfigs() {
    final raw = _ref.read(Preferences.tikNetCachedConfig);
    if (raw.isEmpty) return '';
    try {
      final bytes = base64Decode(raw);
      return utf8.decode(bytes);
    } catch (_) {
      return '';
    }
  }

  /// True if cached profile has expire_date in the past. False if no profile or expire_date is null.
  bool isSubscriptionExpired() {
    final profile = getProfile();
    final exp = profile?.expireDate;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  DateTime? getLastSyncTime() => _ref.read(Preferences.tikNetLastSyncTime);
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref));
