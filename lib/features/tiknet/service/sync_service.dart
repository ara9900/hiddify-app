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
import 'package:hiddify/features/tiknet/service/server_catalog_provider.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';
import 'package:hiddify/features/tiknet/service/tiknet_node_meta.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_ping_settings.dart';
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

  /// Fetches profile, aggregated subscription, catalog configs → one merged profile.
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
      await applyPanelPingSettingsFromBrand(_ref, profile.brand);

      List<int> subBytes = const [];
      try {
        subBytes = await api.getSubscriptionConfig(baseUrl: baseUrl, accessToken: token);
      } catch (_) {}

      var displayMode = TikNetServerDisplayMode.fromApi(_ref.read(Preferences.tikNetServerDisplayMode));
      List<TikNetServerEntry> catalogServers = const [];
      try {
        final catalogData = await api.getServerCatalog(baseUrl: baseUrl, accessToken: token);
        var modeRaw = (catalogData['display_mode'] as String?)?.trim();
        if (modeRaw == null || modeRaw.isEmpty) {
          try {
            final appConfig = await api.getAppConfig(baseUrl: baseUrl, accessToken: token);
            final serverDisplay = appConfig['server_display'];
            if (serverDisplay is Map) {
              await applyPanelServerDisplaySettings(_ref, Map<String, dynamic>.from(serverDisplay));
            }
            await applyPanelPingSettingsFromAppConfig(_ref, appConfig);
            modeRaw = _ref.read(Preferences.tikNetServerDisplayMode);
          } catch (_) {}
        } else if (modeRaw.isNotEmpty) {
          final current = _ref.read(Preferences.tikNetServerDisplayMode);
          if (current != modeRaw) {
            await _ref.read(Preferences.tikNetServerDisplayMode.notifier).update(modeRaw);
          }
        }
        displayMode = TikNetServerDisplayMode.fromApi(modeRaw ?? _ref.read(Preferences.tikNetServerDisplayMode));
        final parsed = TikNetServerCatalog.fromJson(catalogData);
        if (displayMode != TikNetServerDisplayMode.personalOnly) {
          catalogServers = parsed.servers.where((s) => s.accessible && s.id > 0).toList();
        }
      } catch (_) {}

      final includeSub = displayMode != TikNetServerDisplayMode.catalogOnly;
      final catalogInputs = <TikNetCatalogConfigInput>[];
      if (catalogServers.isNotEmpty) {
        catalogInputs.addAll(await _fetchCatalogConfigsParallel(api, baseUrl: baseUrl, token: token, servers: catalogServers));
      }

      final subRaw = includeSub && subBytes.isNotEmpty ? utf8.decode(subBytes, allowMalformed: true) : null;
      final merged = mergeTikNetConfigs(subscriptionRaw: subRaw, catalogConfigs: catalogInputs);
      final nodeCount = merged.nodes.length;

      if (merged.isEmpty) {
        // Fallbacks: raw sub alone, or remote subscription URL.
        if (includeSub && subBytes.isNotEmpty) {
          await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(subBytes));
          await applyProfileFromCache();
        } else {
          final okRemote = await applyRemoteSubscriptionProfile();
          if (!okRemote) return false;
        }
      } else {
        final mergedBytes = utf8.encode(merged.configJson);
        await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(mergedBytes));
        await _ref.read(Preferences.tikNetNodeMetaJson.notifier).update(encodeTikNetNodeMeta(merged.nodes));
        await applyProfileFromCache();
      }
      _ref.invalidate(personalOutboundProvider);
      _ref.invalidate(serverCatalogProvider);

      await _ref.read(Preferences.tikNetLastSyncTime.notifier).update(DateTime.now());

      try {
        final appConfig = await api.getAppConfig(baseUrl: baseUrl, accessToken: token);
        final serverDisplay = appConfig['server_display'];
        if (serverDisplay is Map) {
          await applyPanelServerDisplaySettings(_ref, Map<String, dynamic>.from(serverDisplay));
        }
        await applyPanelPingSettingsFromAppConfig(_ref, appConfig);
      } catch (_) {}

      await auth.extendSession();
      unawaited(_ref.read(tikNetDeviceServiceProvider).registerIfLoggedIn());
      if (tikNetMode) {
        TikNetDiagnosticLog.i('sync', 'syncAll merged ok', {
          'profile_id': _ref.read(Preferences.tikNetProfileId),
          'nodes': nodeCount,
          'catalog_fetched': catalogInputs.length,
        });
      }
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

  Future<List<TikNetCatalogConfigInput>> _fetchCatalogConfigsParallel(
    TikNetApi api, {
    required String baseUrl,
    required String token,
    required List<TikNetServerEntry> servers,
  }) async {
    const concurrency = 4;
    final out = <TikNetCatalogConfigInput>[];
    for (var i = 0; i < servers.length; i += concurrency) {
      final chunk = servers.skip(i).take(concurrency).toList();
      final results = await Future.wait(
        chunk.map((s) async {
          try {
            final bytes = await api
                .getServerConfig(baseUrl: baseUrl, accessToken: token, serverId: s.id)
                .timeout(const Duration(seconds: 12));
            if (bytes.isEmpty) return null;
            return TikNetCatalogConfigInput(server: s, configBytes: bytes);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final r in results) {
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  /// Ensure merged profile is active; outbound pick happens after connect.
  Future<bool> applySelectedServerConfig() async {
    final auth = _ref.read(authServiceProvider);
    if (!auth.hasAppSession()) return false;

    if (_ref.read(Preferences.tikNetProfileId).isNotEmpty) {
      final cached = getConfigs();
      if (cached.trim().isNotEmpty && !isHiddifyXraySubscriptionBundle(cached)) {
        final ok = await applyProfileFromCache();
        if (ok) return true;
      }
    }
    return syncAllAndApplyProfile();
  }

  TikNetServerSelection get selectedServer => parseServerSelection(_ref.read(Preferences.tikNetSelectedServer));

  Future<void> setSelectedServer(TikNetServerSelection selection) async {
    await _ref.read(Preferences.tikNetSelectedServer.notifier).update(encodeServerSelection(selection));
    // New pick starts a fresh smart session (lock cleared until next connect).
    await _ref.read(Preferences.tikNetSmartLockedTag.notifier).update('');
    await _ref.read(Preferences.tikNetSmartLockedGroup.notifier).update('');
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

    var existing = await _findTikNetProfile(repo);
    if (existing is RemoteProfileEntity && existing.url.trim() == subUrl.trim()) {
      await _ref.read(Preferences.tikNetProfileId.notifier).update(existing.id);
      await repo.setAsActive(existing.id).run();
      _ref.invalidate(personalOutboundProvider);
      return true;
    }

    await _abortVpnIfNeeded();

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
    return true;
  }

  Future<bool> _applyLocalProfileContent(String content) async {
    final repo = await _ref.read(profileRepositoryProvider.future);
    final pathResolver = _ref.read(profilePathResolverProvider);
    final userOverride = UserOverride(name: tikNetProfileDisplayName);

    var existing = await _findTikNetProfile(repo);

    if (existing != null && _profileContentMatches(existing.id, content, pathResolver)) {
      await _ref.read(Preferences.tikNetProfileId.notifier).update(existing.id);
      await repo.setAsActive(existing.id).run();
      _ref.invalidate(personalOutboundProvider);
      return true;
    }

    await _abortVpnIfNeeded();

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
    return true;
  }

  Future<void> _abortVpnIfNeeded() async {
    final connection = switch (_ref.read(connectionNotifierProvider)) {
      AsyncData<ConnectionStatus>(value: final status) => status,
      _ => null,
    };
    if (connection is Connected || connection is Connecting || connection is Disconnecting) {
      final preserveIntent = tikNetMode && _ref.read(Preferences.startedByUser);
      await _ref.read(connectionNotifierProvider.notifier).abortConnection(preserveUserIntent: preserveIntent);
      if (preserveIntent) {
        unawaited(_ref.read(connectionNotifierProvider.notifier).restoreVpnSessionIfNeeded());
      }
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
