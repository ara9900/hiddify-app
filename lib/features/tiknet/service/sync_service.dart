import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/service/tiknet_device_service.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/tiknet_outbound_apply.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_network.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_server_display.dart';

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
    if (!auth.hasAppSession()) return false;

    final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    final token = auth.getToken();
    if (baseUrl.isEmpty || token.isEmpty) return false;

    final api = _ref.read(tikNetApiProvider);

    try {
      final profile = await api.getMe(baseUrl: baseUrl, accessToken: token);
      if (profile.subscriptionUrl != null && profile.subscriptionUrl!.trim().isNotEmpty) {
        await _ref.read(Preferences.tikNetSubscriptionUrl.notifier).update(profile.subscriptionUrl!.trim());
      }
      final profileJson = _profileToJson(profile);
      await _ref.read(Preferences.tikNetCachedProfile.notifier).update(jsonEncode(profileJson));

      final configBytes = await _fetchConfigBytes(api, baseUrl: baseUrl, token: token);
      if (configBytes.isEmpty) return false;
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(configBytes));
      await applyProfileFromCache();
      _ref.invalidate(personalOutboundProvider);

      await _ref.read(Preferences.tikNetLastSyncTime.notifier).update(DateTime.now());

      try {
        final appConfig = await api.getAppConfig(baseUrl: baseUrl, accessToken: token);
        final network = appConfig['network'];
        if (network is Map) {
          await applyPanelNetworkSettings(_ref, Map<String, dynamic>.from(network));
        }
        final serverDisplay = appConfig['server_display'];
        if (serverDisplay is Map) {
          await applyPanelServerDisplaySettings(_ref, Map<String, dynamic>.from(serverDisplay));
        }
      } catch (_) {
        // app-config is best-effort; sync profile/config still succeeded
      }

      await auth.extendSession();
      unawaited(_ref.read(tikNetDeviceServiceProvider).registerIfLoggedIn());
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && await auth.clearSessionIfUnauthorized()) {
        throw SyncTokenExpiredException();
      }
      return false;
    } on TikNetApiException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fetch and apply config for current server selection (personal or catalog).
  Future<bool> applySelectedServerConfig() async {
    final auth = _ref.read(authServiceProvider);
    if (!auth.hasAppSession()) return false;
    final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    final token = auth.getToken();
    if (baseUrl.isEmpty || token.isEmpty) return false;

    final selection = parseServerSelection(_ref.read(Preferences.tikNetSelectedServer));
    if (selection.isPersonal && _ref.read(Preferences.tikNetProfileId).isNotEmpty) {
      final cached = getConfigs();
      if (isHiddifyXraySubscriptionBundle(cached)) {
        return applyRemoteSubscriptionProfile();
      }
      return true;
    }

    final api = _ref.read(tikNetApiProvider);
    try {
      final configBytes = await _fetchConfigBytes(api, baseUrl: baseUrl, token: token);
      if (configBytes.isEmpty) return false;
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(configBytes));
      await applyProfileFromCache();
      _ref.invalidate(personalOutboundProvider);
      await _ref.read(Preferences.tikNetLastSyncTime.notifier).update(DateTime.now());
      await auth.extendSession();
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && await auth.clearSessionIfUnauthorized()) {
        throw SyncTokenExpiredException();
      }
      return false;
    } on TikNetApiException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>> _fetchConfigBytes(TikNetApi api, {required String baseUrl, required String token}) async {
    final selection = parseServerSelection(_ref.read(Preferences.tikNetSelectedServer));
    if (selection.isPersonal || selection.catalogId == null) {
      return api.getSubscriptionConfig(baseUrl: baseUrl, accessToken: token);
    }
    return api.getServerConfig(
      baseUrl: baseUrl,
      accessToken: token,
      serverId: selection.catalogId!,
    );
  }

  TikNetServerSelection get selectedServer => parseServerSelection(_ref.read(Preferences.tikNetSelectedServer));

  Future<void> setSelectedServer(TikNetServerSelection selection) async {
    await _ref.read(Preferences.tikNetSelectedServer.notifier).update(encodeServerSelection(selection));
  }

  /// Downloads subscription on device (same path as stock Hiddify). Used when panel bytes do not list nodes.
  Future<bool> applyRemoteSubscriptionProfile() async {
    final subUrl = normalizeSubscriptionFetchUrl(_ref.read(Preferences.tikNetSubscriptionUrl));
    if (!subUrl.toLowerCase().startsWith('http')) return false;
    return _applyRemoteSubscriptionProfile(subUrl);
  }

  /// Applies cached panel config to local Hiddify profile [tikNetProfileDisplayName].
  Future<bool> applyProfileFromCache() async {
    final content = getConfigs();
    if (content.trim().isEmpty) return false;
    return _applyProfileContent(content);
  }

  Future<bool> _applyProfileContent(String content) async {
    final subUrl = normalizeSubscriptionFetchUrl(_ref.read(Preferences.tikNetSubscriptionUrl));
    if (isHiddifyXraySubscriptionBundle(content) ||
        shouldFetchSubscriptionOnDevice(content, subUrl)) {
      return _applyRemoteSubscriptionProfile(subUrl);
    }
    return _applyLocalProfileContent(content);
  }

  Future<bool> _applyRemoteSubscriptionProfile(String subUrl) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final userOverride = UserOverride(name: tikNetProfileDisplayName);
    await _abortVpnIfNeeded();

    var existing = await _findTikNetProfile(repo);
    if (existing != null && existing is! RemoteProfileEntity) {
      await repo.deleteById(existing.id, existing.active).run();
      existing = null;
      await _ref.read(Preferences.tikNetProfileId.notifier).update('');
    }

    if (existing != null && existing is RemoteProfileEntity && existing.url.trim() != subUrl.trim()) {
      await repo.deleteById(existing.id, existing.active).run();
      existing = null;
      await _ref.read(Preferences.tikNetProfileId.notifier).update('');
    }

    final result = await repo.upsertRemote(subUrl, userOverride: userOverride).run();
    if (result.isLeft()) return false;

    final profile = await _findTikNetProfile(repo);
    final profileId = profile?.id;
    if (profileId == null || profileId.isEmpty) return false;

    await _ref.read(Preferences.tikNetProfileId.notifier).update(profileId);
    await repo.setAsActive(profileId).run();
    _ref.invalidate(personalOutboundProvider);
    await applyTikNetPersonalOutboundSelection(_ref);
    return true;
  }

  Future<bool> _applyLocalProfileContent(String content) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final pathResolver = _ref.read(profilePathResolverProvider);
    final userOverride = UserOverride(name: tikNetProfileDisplayName);
    await _abortVpnIfNeeded();

    var existing = await _findTikNetProfile(repo);

    if (existing != null && _profileContentMatches(existing.id, content, pathResolver)) {
      await _ref.read(Preferences.tikNetProfileId.notifier).update(existing.id);
      await repo.setAsActive(existing.id).run();
      _ref.invalidate(personalOutboundProvider);
      return true;
    }

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
    _ref.invalidate(personalOutboundProvider);
    await applyTikNetPersonalOutboundSelection(_ref);
    return true;
  }

  Future<void> _abortVpnIfNeeded() async {
    final connection = _ref.read(connectionNotifierProvider).valueOrNull;
    if (connection is Connected || connection is Connecting || connection is Disconnecting) {
      await _ref.read(connectionNotifierProvider.notifier).abortConnection();
      await _ref.read(Preferences.startedByUser.notifier).update(false);
    }
  }

  bool _profileContentMatches(String profileId, String content, ProfilePathResolver pathResolver) {
    final file = pathResolver.file(profileId);
    if (!file.existsSync()) return false;
    try {
      final onDisk = file.readAsStringSync();
      return onDisk.trim() == content.trim();
    } catch (_) {
      return false;
    }
  }

  Future<ProfileEntity?> _findTikNetProfile(ProfileRepository repo) async {
    final storedId = _ref.read(Preferences.tikNetProfileId);
    if (storedId.isNotEmpty) {
      final stored = await repo.getById(storedId).run();
      if (stored case Right(value: final profile)) {
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
      if (p.subscriptionUrl != null && p.subscriptionUrl!.isNotEmpty) 'subscription_url': p.subscriptionUrl,
      if (p.planName != null) 'plan_name': p.planName,
      if (p.isExpired != null) 'is_expired': p.isExpired,
      if (p.daysRemaining != null) 'days_remaining': p.daysRemaining,
      if (p.trafficUsedBytes != null) 'traffic_used_bytes': p.trafficUsedBytes,
      if (p.trafficLimitBytes != null) 'traffic_limit_bytes': p.trafficLimitBytes,
      'shop_enabled': p.shopEnabled,
      if (p.brand != null && !p.brand!.isEmpty)
        'brand': {
          'name': p.brand!.name,
          'logo_url': p.brand!.logoUrl,
          'primary_color': p.brand!.primaryColor,
          'support_telegram': p.brand!.supportTelegram,
          'api_base_url': p.brand!.apiBaseUrl,
        },
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
