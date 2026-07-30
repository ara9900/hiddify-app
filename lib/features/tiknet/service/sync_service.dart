import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
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
import 'package:hiddify/features/tiknet/model/tiknet_entitlement.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/service/tiknet_device_service.dart';
import 'package:hiddify/features/tiknet/service/personal_outbound_provider.dart';
import 'package:hiddify/features/tiknet/service/server_catalog_provider.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';
import 'package:hiddify/features/tiknet/service/tiknet_node_meta.dart';
import 'package:hiddify/features/tiknet/service/tiknet_subscription_sanitizer.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_ping_settings.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_server_display.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/link_parsers.dart';

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

  Future<bool>? _syncInFlight;

  /// Fetches profile + config from panel, caches them, imports config into Hiddify profile.
  Future<bool> syncAllAndApplyProfile() async {
    final synced = await syncAll();
    if (!synced) return false;
    return applyProfileFromCache();
  }

  /// Fetches profile, aggregated subscription, catalog configs → one merged profile.
  Future<bool> syncAll() {
    // Concurrent syncAll (session guard + UI) raced the convert gate and deadlocked
    // cold-start validateConfig. Coalesce to one in-flight sync.
    return _syncInFlight ??= _syncAllBody().whenComplete(() => _syncInFlight = null);
  }

  Future<bool> _syncAllBody() async {
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

      // Personal nodes die on the panel when volume/time ends or the account is
      // disabled. Catalog (emergency free) servers do not — gate them here too.
      final entitlement = evaluateTikNetEntitlement(profile);
      if (!entitlement.allowed) {
        await _abortVpnForEntitlementBlock(entitlement);
        await _resetRestrictedSelections();
      }

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
        // Still list catalog in the picker (as locked) when ineligible, but never
        // merge free emergency outbounds into the live profile.
        if (displayMode != TikNetServerDisplayMode.personalOnly && !entitlement.blocksCatalog) {
          catalogServers = parsed.servers.where((s) => s.accessible && s.id > 0).toList();
        } else if (entitlement.blocksCatalog && tikNetMode) {
          TikNetDiagnosticLog.i('sync', 'skip catalog merge — entitlement blocked', {
            'block': entitlement.block?.name,
          });
        }
        if (tikNetMode) {
          TikNetDiagnosticLog.i('sync', 'catalog list', {
            'mode': displayMode.name,
            'listed': parsed.servers.length,
            'accessible': catalogServers.length,
            'ids': catalogServers.map((s) => s.id).take(12).toList(),
          });
        }
      } catch (e) {
        if (tikNetMode) {
          TikNetDiagnosticLog.w('sync', 'catalog list fetch failed', {'err': e.toString()});
        }
      }

      final includeSub = displayMode != TikNetServerDisplayMode.catalogOnly;
      final rawSub = includeSub && subBytes.isNotEmpty ? utf8.decode(subBytes, allowMalformed: true) : null;
      final sanitized = rawSub == null ? null : sanitizeSubscriptionPayload(rawSub);
      if (tikNetMode && sanitized != null && sanitized.changed) {
        TikNetDiagnosticLog.i('sync', 'dropped info entries from subscription', {
          'count': sanitized.droppedLabels.length,
          'labels': sanitized.droppedLabels.take(6).toList(),
        });
      }
      final subRawPayload = sanitized?.payload;

      // Apply personal first so cold start is not blocked on catalog share-link convert.
      if (includeSub && subRawPayload != null && subRawPayload.trim().isNotEmpty) {
        if (subRawPayload.trim().startsWith('{')) {
          await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(utf8.encode(subRawPayload)));
          await applyProfileFromCache();
        } else {
          final disk = await _readActiveProfileJson();
          final diskHasPersonal = disk != null &&
              mergeTikNetConfigs(subscriptionRaw: disk, catalogConfigs: const [])
                  .nodes
                  .any((n) => !n.isCatalog);
          if (diskHasPersonal) {
            if (tikNetMode) {
              TikNetDiagnosticLog.i('sync', 'skip remote personal apply — on-disk profile already has personal nodes');
            }
          } else {
            try {
              final okRemote = await applyRemoteSubscriptionProfile().timeout(const Duration(seconds: 25));
              if (!okRemote && tikNetMode) {
                TikNetDiagnosticLog.w('sync', 'personal remote profile apply failed — will still try catalog merge');
              }
            } on TimeoutException {
              TikNetDiagnosticLog.w('sync', 'personal remote profile apply timed out — continuing to catalog');
            }
          }
        }
      }

      final catalogInputs = <TikNetCatalogConfigInput>[];
      if (catalogServers.isNotEmpty) {
        catalogInputs.addAll(await _fetchCatalogConfigsParallel(api, baseUrl: baseUrl, token: token, servers: catalogServers));
      }

      final subRaw = catalogInputs.isEmpty
          ? subRawPayload
          : await _resolveSubscriptionJsonForMerge(subRawPayload);
      final merged = mergeTikNetConfigs(subscriptionRaw: subRaw, catalogConfigs: catalogInputs);
      final nodeCount = merged.nodes.length;

      if (entitlement.blocksCatalog) {
        await _applyProfileWithoutCatalog(
          includeSub: includeSub,
          subRaw: subRawPayload,
          merged: merged,
        );
      } else if (merged.isEmpty) {
        // Personal may already be on disk from the earlier apply/skip path.
        final disk = await _readActiveProfileJson();
        final diskHasPersonal = disk != null &&
            mergeTikNetConfigs(subscriptionRaw: disk, catalogConfigs: const [])
                .nodes
                .any((n) => !n.isCatalog);
        if (diskHasPersonal) {
          if (tikNetMode) {
            TikNetDiagnosticLog.w(
              'sync',
              'merge empty after catalog convert miss — kept on-disk personal profile',
              {'catalog_servers': catalogServers.length, 'configs_ok': catalogInputs.length},
            );
          }
        } else {
          try {
            final okRemote = await applyRemoteSubscriptionProfile().timeout(const Duration(seconds: 25));
            if (!okRemote && includeSub && subRawPayload != null && subRawPayload.trim().startsWith('{')) {
              await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(utf8.encode(subRawPayload)));
              await applyProfileFromCache();
            } else if (!okRemote && tikNetMode) {
              TikNetDiagnosticLog.w('sync', 'merge empty - kept previous profile (share-link apply skipped)');
            }
          } on TimeoutException {
            TikNetDiagnosticLog.w('sync', 'merge-empty remote apply timed out');
          }
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
        final mergedCatalogCount = merged.nodes.where((n) => n.isCatalog).length;
        TikNetDiagnosticLog.i('sync', 'syncAll merged ok', {
          'profile_id': _ref.read(Preferences.tikNetProfileId),
          'nodes': nodeCount,
          'catalog_fetched': catalogInputs.length,
          'catalog_nodes': mergedCatalogCount,
        });
        if (catalogServers.isNotEmpty && mergedCatalogCount == 0) {
          TikNetDiagnosticLog.w(
            'sync',
            'accessible catalog servers but no catalog nodes in merge — user should refresh again',
            {'accessible': catalogServers.length, 'configs_ok': catalogInputs.length},
          );
        }
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
    // Fetch in parallel, but normalize/convert serially — concurrent validateConfig
    // against a cold core hangs and never returns.
    const fetchConcurrency = 4;
    final fetched = <({TikNetServerEntry server, List<int> bytes})>[];
    for (var i = 0; i < servers.length; i += fetchConcurrency) {
      final chunk = servers.skip(i).take(fetchConcurrency).toList();
      final results = await Future.wait(
        chunk.map((s) async {
          try {
            final bytes = await api
                .getServerConfig(baseUrl: baseUrl, accessToken: token, serverId: s.id)
                .timeout(const Duration(seconds: 12));
            if (bytes.isEmpty) {
              if (tikNetMode) {
                TikNetDiagnosticLog.w('sync', 'catalog config empty', {'id': s.id, 'name': s.name});
              }
              return null;
            }
            return (server: s, bytes: bytes);
          } catch (e) {
            if (tikNetMode) {
              TikNetDiagnosticLog.w('sync', 'catalog config fetch failed', {
                'id': s.id,
                'name': s.name,
                'err': e.toString(),
              });
            }
            return null;
          }
        }),
      );
      for (final r in results) {
        if (r != null) fetched.add(r);
      }
    }

    final out = <TikNetCatalogConfigInput>[];
    for (final item in fetched) {
      final normalized = await _normalizeCatalogConfigBytes(
        item.bytes,
        catalogId: item.server.id,
        name: item.server.name,
      );
      if (normalized != null) {
        out.add(TikNetCatalogConfigInput(server: item.server, configBytes: normalized));
      }
    }
    return out;
  }

  /// Prefer JSON subscription (or on-disk profile) so catalog merge keeps personal nodes.
  Future<String?> _resolveSubscriptionJsonForMerge(String? subRawPayload) async {
    final trimmed = subRawPayload?.trim() ?? '';
    if (trimmed.startsWith('{')) return trimmed;

    if (trimmed.isNotEmpty) {
      final converted = await _convertPanelConfigToSingboxJson(utf8.encode(trimmed));
      if (converted != null && converted.trim().startsWith('{')) {
        if (tikNetMode) {
          TikNetDiagnosticLog.i('sync', 'subscription share-link converted for catalog merge');
        }
        return converted;
      }
    }

    final cached = getConfigs().trim();
    if (cached.startsWith('{')) {
      final personal = mergeTikNetConfigs(subscriptionRaw: cached, catalogConfigs: const []);
      if (personal.nodes.any((n) => !n.isCatalog)) {
        if (tikNetMode) {
          TikNetDiagnosticLog.i('sync', 'using cached JSON subscription base for catalog merge', {
            'personal_nodes': personal.nodes.where((n) => !n.isCatalog).length,
          });
        }
        return cached;
      }
    }

    final fromDisk = await _readActiveProfileJson();
    if (fromDisk != null) {
      final personal = mergeTikNetConfigs(subscriptionRaw: fromDisk, catalogConfigs: const []);
      if (personal.nodes.any((n) => !n.isCatalog)) {
        if (tikNetMode) {
          TikNetDiagnosticLog.i('sync', 'using on-disk profile as subscription base for catalog merge', {
            'personal_nodes': personal.nodes.where((n) => !n.isCatalog).length,
          });
        }
        return fromDisk;
      }
    }

    if (tikNetMode && trimmed.isNotEmpty) {
      TikNetDiagnosticLog.w('sync', 'subscription still share-link — catalog merge may be catalog-only');
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<String?> _readActiveProfileJson() async {
    try {
      final id = _ref.read(Preferences.tikNetProfileId).trim();
      if (id.isEmpty) return null;
      final file = _ref.read(profilePathResolverProvider).file(id);
      if (!file.existsSync()) return null;
      final text = file.readAsStringSync().trim();
      return text.startsWith('{') ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// Panel may ship catalog configs as share-links (`vless://…`). Convert to sing-box JSON.
  Future<List<int>?> _normalizeCatalogConfigBytes(
    List<int> bytes, {
    required int catalogId,
    required String name,
  }) async {
    if (_peekCatalogExtractCount(bytes, catalogId: catalogId, name: name) > 0) {
      return bytes;
    }
    final converted = await _convertPanelConfigToSingboxJson(bytes);
    if (converted == null || converted.trim().isEmpty) {
      TikNetDiagnosticLog.w('sync', 'catalog config not parseable as outbounds', {
        'id': catalogId,
        'name': name,
        'bytes': bytes.length,
        'head': utf8.decode(bytes.take(80).toList(), allowMalformed: true),
      });
      return null;
    }
    final convertedBytes = utf8.encode(converted);
    if (_peekCatalogExtractCount(convertedBytes, catalogId: catalogId, name: name) <= 0) {
      TikNetDiagnosticLog.w('sync', 'catalog convert produced no selectable outbounds', {
        'id': catalogId,
        'name': name,
      });
      return null;
    }
    TikNetDiagnosticLog.i('sync', 'catalog share-link converted', {'id': catalogId, 'name': name});
    return convertedBytes;
  }

  /// Ensure merged profile is active; outbound pick happens after connect.
  Future<bool> applySelectedServerConfig() async {
    final auth = _ref.read(authServiceProvider);
    if (!auth.hasAppSession()) return false;

    final entitlement = currentEntitlement();
    final sel = selectedServer;
    if (entitlement.blocksCatalog && selectionUsesCatalog(sel)) {
      await _resetRestrictedSelections();
      TikNetDiagnosticLog.w('sync', 'refuse catalog apply — entitlement blocked', {
        'block': entitlement.block?.name,
      });
      return false;
    }

    // Catalog picks must refresh+merge the selected server into the live profile.
    // Re-applying a stale personal-only cache is what made Turkey show as selected
    // while traffic kept exiting via Germany.
    if (selectionUsesCatalog(sel)) {
      final id = sel.catalogId ?? catalogIdFromOutboundTag(sel.personalTag);
      TikNetDiagnosticLog.i('sync', 'apply catalog selection', {'id': id, 'raw': encodeServerSelection(sel)});
      final ok = await ensureCatalogServerInProfile(id);
      if (!ok) {
        TikNetDiagnosticLog.w('sync', 'catalog selection not in profile after sync/inject', {'id': id});
      }
      return ok;
    }

    if (_ref.read(Preferences.tikNetProfileId).isNotEmpty) {
      final cached = getConfigs();
      if (cached.trim().isNotEmpty && !isHiddifyXraySubscriptionBundle(cached)) {
        final ok = await applyProfileFromCache();
        if (ok) return true;
      }
    }
    return syncAllAndApplyProfile();
  }

  /// True when node meta (or tag heuristic) already has this catalog server.
  bool profileHasCatalogServer(int catalogId) {
    if (catalogId <= 0) return false;
    final meta = decodeTikNetNodeMeta(_ref.read(Preferences.tikNetNodeMetaJson));
    if (meta.values.any((n) => n.catalogId == catalogId)) return true;
    final raw = getConfigs();
    if (raw.trim().isEmpty) return false;
    return RegExp('cat-$catalogId-').hasMatch(raw);
  }

  /// Sync, then if needed fetch+merge the specific catalog server so selection can dial it.
  Future<bool> ensureCatalogServerInProfile(int? catalogId) async {
    if (catalogId == null || catalogId <= 0) return false;

    final synced = await syncAllAndApplyProfile();
    if (profileHasCatalogServer(catalogId)) {
      if (synced) return true;
      return await applyProfileFromCache();
    }

    final injected = await _injectCatalogServer(catalogId);
    return injected;
  }

  Future<bool> _injectCatalogServer(int catalogId) async {
    final auth = _ref.read(authServiceProvider);
    final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    final token = auth.getToken();
    if (baseUrl.isEmpty || token.isEmpty) return false;

    final api = _ref.read(tikNetApiProvider);
    TikNetServerEntry? server;
    try {
      final catalogData = await api.getServerCatalog(baseUrl: baseUrl, accessToken: token);
      final parsed = TikNetServerCatalog.fromJson(catalogData);
      server = parsed.servers.where((s) => s.id == catalogId).firstOrNull;
    } catch (e) {
      TikNetDiagnosticLog.w('sync', 'catalog list fetch failed during inject', {
        'id': catalogId,
        'err': e.toString(),
      });
    }
    server ??= TikNetServerEntry(
      id: catalogId,
      name: 'سرور #$catalogId',
      countryCode: '',
      tier: 'free',
      sourceType: 'catalog',
      requiresPaid: false,
      accessible: true,
      sortOrder: 0,
    );
    if (!server.accessible) {
      TikNetDiagnosticLog.w('sync', 'catalog server not accessible', {'id': catalogId});
      return false;
    }

    List<int> bytes;
    try {
      bytes = await api
          .getServerConfig(baseUrl: baseUrl, accessToken: token, serverId: catalogId)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      TikNetDiagnosticLog.w('sync', 'catalog config fetch failed', {
        'id': catalogId,
        'err': e.toString(),
      });
      return false;
    }
    if (bytes.isEmpty) {
      TikNetDiagnosticLog.w('sync', 'catalog config empty', {'id': catalogId});
      return false;
    }

    var configBytes = bytes;
    final normalized = await _normalizeCatalogConfigBytes(bytes, catalogId: catalogId, name: server.name);
    if (normalized == null) return false;
    configBytes = normalized;

    // Prefer a JSON subscription base when available.
    var subRaw = getConfigs();
    if (subRaw.trim().isEmpty) {
      try {
        final subBytes = await api.getSubscriptionConfig(baseUrl: baseUrl, accessToken: token);
        if (subBytes.isNotEmpty) {
          subRaw = sanitizeSubscriptionPayload(utf8.decode(subBytes, allowMalformed: true)).payload;
        }
      } catch (_) {}
    } else {
      final sanitized = sanitizeSubscriptionPayload(subRaw);
      subRaw = sanitized.payload;
    }
    if (subRaw.trim().isNotEmpty && !subRaw.trim().startsWith('{')) {
      subRaw = (await _resolveSubscriptionJsonForMerge(subRaw)) ?? subRaw;
    }

    final merged = mergeTikNetConfigs(
      subscriptionRaw: subRaw.trim().isEmpty ? null : subRaw,
      catalogConfigs: [TikNetCatalogConfigInput(server: server, configBytes: configBytes)],
    );
    if (merged.isEmpty || !merged.nodes.any((n) => n.catalogId == catalogId)) {
      TikNetDiagnosticLog.w('sync', 'catalog inject merge empty', {'id': catalogId});
      return false;
    }

    await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(utf8.encode(merged.configJson)));
    await _ref.read(Preferences.tikNetNodeMetaJson.notifier).update(encodeTikNetNodeMeta(merged.nodes));
    final ok = await applyProfileFromCache();
    TikNetDiagnosticLog.i('sync', 'catalog inject ok', {
      'id': catalogId,
      'nodes': merged.nodes.length,
      'applied': ok,
    });
    _ref.invalidate(personalOutboundProvider);
    _ref.invalidate(serverCatalogProvider);
    return ok && profileHasCatalogServer(catalogId);
  }

  int _peekCatalogExtractCount(List<int> bytes, {required int catalogId, required String name}) {
    final merged = mergeTikNetConfigs(
      catalogConfigs: [
        TikNetCatalogConfigInput(
          server: TikNetServerEntry(
            id: catalogId,
            name: name,
            countryCode: '',
            tier: 'free',
            sourceType: 'catalog',
            requiresPaid: false,
            accessible: true,
            sortOrder: 0,
          ),
          configBytes: bytes,
        ),
      ],
    );
    return merged.nodes.where((n) => n.catalogId == catalogId).length;
  }

  /// Serialize converts — parallel validateConfig calls deadlock a cold core.
  Future<void> _convertGate = Future<void>.value();

  /// Convert share-link / non-JSON panel payloads to sing-box JSON via core validate.
  ///
  /// Matches [ProfileRepository.addLocal]: write source to `*.tmp`, validate writes
  /// the converted JSON to the main path. Each attempt is hard-timed-out so sync
  /// cannot hang forever when gRPC is refused during startup.
  Future<String?> _convertPanelConfigToSingboxJson(List<int> bytes) async {
    // Assign the next gate slot BEFORE awaiting the previous one so concurrent
    // callers cannot both attach to the same prior future (classic mutex race).
    final prior = _convertGate;
    final slot = Completer<void>();
    _convertGate = slot.future;
    try {
      try {
        await prior;
      } catch (_) {}
      return await _convertPanelConfigToSingboxJsonUnlocked(bytes);
    } finally {
      if (!slot.isCompleted) slot.complete();
    }
  }

  Future<String?> _convertPanelConfigToSingboxJsonUnlocked(List<int> bytes) async {
    var text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) return text;
    if (!text.contains('://')) {
      final decoded = safeDecodeBase64(text).trim();
      if (decoded.startsWith('{') || decoded.contains('://')) text = decoded;
    }
    if (text.startsWith('{')) return text;

    try {
      // Cold start: fgClient is late-initialized; force setup before parse or
      // validateConfig throws LateInitializationError and aborts convert.
      try {
        final setupResult = await _ref
            .read(hiddifyCoreServiceProvider)
            .setup()
            .run()
            .timeout(const Duration(seconds: 15));
        if (setupResult.isLeft()) {
          TikNetDiagnosticLog.w('sync', 'core setup before convert failed', {
            'err': setupResult.fold((l) => l.toString(), (_) => 'unknown'),
          });
        }
      } on Object catch (e) {
        TikNetDiagnosticLog.w('sync', 'core setup before convert failed', {'err': e.toString()});
      }

      final repo = await _ref.read(profileRepositoryProvider.future);
      final paths = _ref.read(profilePathResolverProvider);
      final convertId = 'tiknet-cat-convert-${DateTime.now().microsecondsSinceEpoch}';
      final file = paths.file(convertId);
      final temp = paths.tempFile(convertId);
      await file.parent.create(recursive: true);
      if (file.existsSync()) file.deleteSync();
      if (temp.existsSync()) temp.deleteSync();
      await temp.writeAsString(text);

      Object? lastErr;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) await Future<void>.delayed(Duration(seconds: 2 * attempt));
        try {
          final result = await repo
              .validateConfig(file.path, temp.path, null, false)
              .run()
              .timeout(const Duration(seconds: 12));
          final out = result.fold<(String?, Object?)>((l) => (null, l), (_) {
            if (!file.existsSync()) return (null, 'converted file missing');
            final json = file.readAsStringSync().trim();
            return (json.isEmpty ? null : json, json.isEmpty ? 'empty convert output' : null);
          });
          if (out.$1 != null && out.$1!.startsWith('{')) {
            try {
              file.deleteSync();
            } catch (_) {}
            try {
              temp.deleteSync();
            } catch (_) {}
            return out.$1;
          }
          lastErr = out.$2 ?? lastErr;
        } on TimeoutException {
          lastErr = 'validateConfig timed out';
          TikNetDiagnosticLog.w('sync', 'catalog convert timed out', {'attempt': attempt + 1});
        }
      }
      TikNetDiagnosticLog.w('sync', 'catalog convert failed', {
        'err': lastErr?.toString() ?? 'unknown',
        'head': text.length > 80 ? text.substring(0, 80) : text,
      });
      try {
        file.deleteSync();
      } catch (_) {}
      try {
        temp.deleteSync();
      } catch (_) {}
      return null;
    } catch (e) {
      TikNetDiagnosticLog.w('sync', 'catalog convert failed', {'err': e.toString()});
      return null;
    }
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
    return _applyProfileContentWithRetry(content);
  }

  /// A cold-start sync races the core: rewriting a profile needs the core's
  /// gRPC endpoint to convert and validate it, and until the service is up that
  /// call is refused, leaving the core on the previous config. Retry while it
  /// starts instead of failing silently.
  static const _applyRetryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
  ];

  Future<bool> _applyProfileContentWithRetry(String content) async {
    if (await _applyProfileContent(content)) return true;
    for (final delay in _applyRetryDelays) {
      await Future<void>.delayed(delay);
      if (await _applyProfileContent(content)) {
        if (tikNetMode) TikNetDiagnosticLog.i('sync', 'profile applied once core was ready');
        return true;
      }
    }
    if (tikNetMode) {
      TikNetDiagnosticLog.w('sync', 'profile apply failed — core kept the previous config');
    }
    return false;
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

    // Don't delete/recreate remote profile while VPN is connected — that forces reconnect.
    if (tikNetMode && _ref.read(Preferences.startedByUser)) {
      TikNetDiagnosticLog.i('sync', 'skip remote profile replace — VPN stays up');
      return existing != null;
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
    final contentHash = _contentHash(content);

    // Share-link payloads never match the converted file the core writes, so
    // compare against the hash of the last payload the core actually accepted.
    final alreadyApplied = existing != null &&
        (_profileContentMatches(existing.id, content, pathResolver) ||
            (_ref.read(Preferences.tikNetAppliedConfigHash) == contentHash &&
                pathResolver.file(existing.id).existsSync()));
    if (alreadyApplied) {
      await _ref.read(Preferences.tikNetProfileId.notifier).update(existing.id);
      await repo.setAsActive(existing.id).run();
      _ref.invalidate(personalOutboundProvider);
      return true;
    }

    // VPN is up: rewrite the same local profile file without abort/reconnect.
    if (tikNetMode &&
        _ref.read(Preferences.startedByUser) &&
        existing != null &&
        existing is! RemoteProfileEntity) {
      final result = await repo
          .offlineUpdate(existing.copyWith(userOverride: userOverride), content)
          .run();
      if (result.isLeft()) return false;
      await _ref.read(Preferences.tikNetProfileId.notifier).update(existing.id);
      await _ref.read(Preferences.tikNetAppliedConfigHash.notifier).update(contentHash);
      await repo.setAsActive(existing.id).run();
      _ref.invalidate(personalOutboundProvider);
      TikNetDiagnosticLog.i('sync', 'profile updated on disk while VPN stays up');
      return true;
    }

    await _abortVpnIfNeeded();

    if (existing is RemoteProfileEntity) {
      await repo.deleteById(existing.id, existing.active).run();
      existing = null;
      await _ref.read(Preferences.tikNetProfileId.notifier).update('');
    }

    if (existing != null) {
      try {
        final result = await repo
            .offlineUpdate(existing.copyWith(userOverride: userOverride), content)
            .run()
            .timeout(const Duration(seconds: 20));
        if (result.isLeft()) return false;
      } on TimeoutException {
        TikNetDiagnosticLog.w('sync', 'profile offlineUpdate timed out');
        return false;
      }
    } else {
      try {
        final result = await repo.addLocal(content, userOverride: userOverride).run().timeout(const Duration(seconds: 20));
        if (result.isLeft()) return false;
        existing = await _findTikNetProfile(repo);
      } on TimeoutException {
        TikNetDiagnosticLog.w('sync', 'profile addLocal timed out');
        return false;
      }
    }

    final profileId = existing?.id;
    if (profileId == null || profileId.isEmpty) return false;

    await _ref.read(Preferences.tikNetProfileId.notifier).update(profileId);
    await _ref.read(Preferences.tikNetAppliedConfigHash.notifier).update(contentHash);
    await repo.setAsActive(profileId).run();
    _ref.invalidate(personalOutboundProvider);
    return true;
  }

  String _contentHash(String content) => md5.convert(utf8.encode(content)).toString();

  Future<void> _abortVpnIfNeeded() async {
    // Cold-start sync must NEVER kill a live TikNet tunnel just to rewrite the profile.
    // Update on disk instead; tunnel keeps current config until the user reconnects.
    if (tikNetMode && _ref.read(Preferences.startedByUser)) {
      TikNetDiagnosticLog.i('sync', 'skip abortVpn — user VPN intent active');
      return;
    }
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

  /// Volume/time/admin blocks must tear down VPN even when startedByUser is true —
  /// including any catalog (free emergency) tunnel the panel cannot kill itself.
  Future<void> _abortVpnForEntitlementBlock(TikNetEntitlement entitlement) async {
    if (!tikNetMode) return;
    TikNetDiagnosticLog.i('sync', 'entitlement abort VPN', {'block': entitlement.block?.name});
    await _ref.read(connectionNotifierProvider.notifier).forceStopForEntitlementBlock();
  }

  /// Drop catalog picks and any smart-lock stuck on a catalog outbound.
  Future<void> _resetRestrictedSelections() async {
    if (selectionUsesCatalog(selectedServer)) {
      await setSelectedServer(smartSelection());
    }
    final locked = _ref.read(Preferences.tikNetSmartLockedTag).trim();
    if (locked.isNotEmpty && isTikNetCatalogOutboundTag(locked)) {
      await _ref.read(Preferences.tikNetSmartLockedTag.notifier).update('');
      await _ref.read(Preferences.tikNetSmartLockedGroup.notifier).update('');
    }
  }

  /// Rewrite the live profile without catalog leaves. Never leave a stale
  /// merged cache that still contains `cat-{id}-…` outbounds.
  Future<void> _applyProfileWithoutCatalog({
    required bool includeSub,
    required String? subRaw,
    required TikNetMergedConfigResult merged,
  }) async {
    if (!merged.isEmpty) {
      final cleanedJson = stripCatalogOutboundsFromConfig(merged.configJson) ?? merged.configJson;
      final personalNodes = merged.nodes.where((n) => !n.isCatalog).toList();
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(utf8.encode(cleanedJson)));
      await _ref.read(Preferences.tikNetNodeMetaJson.notifier).update(encodeTikNetNodeMeta(personalNodes));
      await applyProfileFromCache();
      return;
    }

    if (includeSub && subRaw != null && subRaw.trim().isNotEmpty) {
      final personalOnly = mergeTikNetConfigs(subscriptionRaw: subRaw, catalogConfigs: const []);
      if (!personalOnly.isEmpty) {
        await _ref
            .read(Preferences.tikNetCachedConfig.notifier)
            .update(base64Encode(utf8.encode(personalOnly.configJson)));
        await _ref.read(Preferences.tikNetNodeMetaJson.notifier).update(encodeTikNetNodeMeta(personalOnly.nodes));
        await applyProfileFromCache();
        return;
      }
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(utf8.encode(subRaw)));
      await _stripCatalogFromNodeMeta();
      await applyProfileFromCache();
      return;
    }

    await _purgeCatalogFromLocalStore();
  }

  Future<void> _purgeCatalogFromLocalStore() async {
    final sources = <String>[];
    final cached = getConfigs();
    if (cached.trim().isNotEmpty) sources.add(cached);

    final profileId = _ref.read(Preferences.tikNetProfileId);
    if (profileId.isNotEmpty) {
      try {
        final repo = await _ref.read(profileRepositoryProvider.future);
        final rawProfile = await repo.getRawConfig(profileId).run();
        rawProfile.fold((_) {}, (c) {
          if (c.trim().isNotEmpty && !sources.contains(c)) sources.add(c);
        });
      } catch (_) {}
    }

    for (final raw in sources) {
      final stripped = stripCatalogOutboundsFromConfig(raw);
      if (stripped == null || stripped.trim().isEmpty) continue;
      await _ref.read(Preferences.tikNetCachedConfig.notifier).update(base64Encode(utf8.encode(stripped)));
      await _stripCatalogFromNodeMeta();
      if (await applyProfileFromCache()) {
        TikNetDiagnosticLog.i('sync', 'purged catalog outbounds from local profile');
        return;
      }
    }

    // No usable personal config left — wipe cache and replace on-disk profile so
    // leftover cat-* outbounds cannot be dialed even if connect is somehow forced.
    await _wipeLocalProfileAfterCatalogBlock();
  }

  static const _directOnlyProfile = '''
{
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {"final": "direct"}
}
''';

  Future<void> _wipeLocalProfileAfterCatalogBlock() async {
    await _ref.read(Preferences.tikNetCachedConfig.notifier).update('');
    await _ref.read(Preferences.tikNetNodeMetaJson.notifier).update('');
    final ok = await _applyLocalProfileContent(_directOnlyProfile);
    TikNetDiagnosticLog.i('sync', 'wiped local profile after catalog block', {'ok': ok});
  }

  Future<void> _stripCatalogFromNodeMeta() async {
    final meta = decodeTikNetNodeMeta(_ref.read(Preferences.tikNetNodeMetaJson));
    final kept = meta.values.where((n) => !n.isCatalog && (n.catalogId == null || n.catalogId! <= 0)).toList();
    await _ref.read(Preferences.tikNetNodeMetaJson.notifier).update(encodeTikNetNodeMeta(kept));
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
      if (p.isActive != null) 'is_active': p.isActive,
      if (p.isBlocked != null) 'is_blocked': p.isBlocked,
      if (p.status != null && p.status!.isNotEmpty) 'status': p.status,
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

  /// Connect + catalog free servers allowed for the cached profile.
  TikNetEntitlement currentEntitlement() => evaluateTikNetEntitlement(getProfile());

  DateTime? getLastSyncTime() => _ref.read(Preferences.tikNetLastSyncTime);
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(ref));
