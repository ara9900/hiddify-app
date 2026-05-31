import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'auth_service.dart';
import 'tiknet_api.dart';

/// Thrown when sync fails due to 401 (token expired). Caller should redirect to login.
class SyncTokenExpiredException implements Exception {
  @override
  String toString() => 'Token expired';
}

const String tikNetProfileDisplayName = 'TikNet';

/// Syncs profile and config from panel API and applies config to Hiddify profile.
class SyncService {
  SyncService(this._ref);
  final Ref _ref;

  /// Fetches profile + config from panel, caches them, imports config into Hiddify profile.
  Future<bool> syncAllAndApplyProfile() async {
    final synced = await syncAll();
    if (!synced) return false;
    return applyProfileFromCache();
  }

  /// Fetches [api_urls] unrelated — profile (GET /api/customer/me) and config (GET /api/customer/subscription/config).
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
      if (configBytes.isEmpty) return false;
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(configBytes));

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

  /// Applies cached panel config to local Hiddify profile [tikNetProfileDisplayName].
  Future<bool> applyProfileFromCache() async {
    final content = getConfigs();
    if (content.trim().isEmpty) return false;
    return _applyProfileContent(content);
  }

  Future<bool> _applyProfileContent(String content) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final userOverride = UserOverride(name: tikNetProfileDisplayName);
    final wasConnected = _ref.read(connectionNotifierProvider).valueOrNull is Connected;

    var existing = await _findTikNetProfile(repo);
    if (existing is RemoteProfileEntity) {
      await repo.deleteById(existing.id, existing.active).run();
      existing = null;
      await _ref.read(Preferences.tikNetProfileId.notifier).update('');
    }

    if (existing != null) {
      final result = await repo
          .offlineUpdate(existing.copyWith(userOverride: userOverride), content)
          .run();
      if (result.isLeft()) return false;
    } else {
      final result = await repo.addLocal(content, userOverride: userOverride).run();
      if (result.isLeft()) return false;
      existing = await _findTikNetProfile(repo);
    }

    final profileId = existing?.id;
    if (profileId == null || profileId.isEmpty) return false;

    await _ref.read(Preferences.tikNetProfileId.notifier).update(profileId);
    await repo.setAsActive(profileId).run();

    if (wasConnected && existing != null) {
      await _ref.read(connectionNotifierProvider.notifier).reconnect(existing);
    }
    return true;
  }

  Future<ProfileEntity?> _findTikNetProfile(ProfileRepository repo) async {
    final storedId = _ref.read(Preferences.tikNetProfileId);
    if (storedId.isNotEmpty) {
      final stored = await repo.getById(storedId).run();
      if (stored case Right(value: final profile?) when profile != null) {
        return profile;
      }
    }

    final listResult = await repo.watchAll().first;
    return listResult.fold((_) => null, (profiles) {
      for (final p in profiles) {
        if (p.userOverride?.name == tikNetProfileDisplayName || p.name == tikNetProfileDisplayName) {
          return p;
        }
      }
      return null;
    });
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
