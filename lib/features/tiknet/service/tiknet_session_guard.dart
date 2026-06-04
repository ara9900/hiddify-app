import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Validates TikNet session on cold start and drops stale backup-restored cache.
Future<void> reconcileTikNetSession(ProviderContainer container) async {
  if (!tikNetMode) return;

  final prefs = container.read(sharedPreferencesProvider).requireValue;
  final token = prefs.getString('tiknet_access_token') ?? '';
  final cachedProfile = prefs.getString('tiknet_cached_profile') ?? '';
  final cachedConfig = prefs.getString('tiknet_cached_config') ?? '';
  final cachedAnnouncement = prefs.getString('tiknet_cached_announcement') ?? '';

  final auth = container.read(authServiceProvider);

  if (token.isEmpty) {
    if (cachedProfile.isNotEmpty || cachedConfig.isNotEmpty || cachedAnnouncement.isNotEmpty) {
      await auth.logout();
      await clearTikNetVpnProfiles(container);
    }
    return;
  }

  final baseUrl = prefs.getString('tiknet_panel_base_url') ?? '';
  if (baseUrl.isEmpty) {
    await auth.logout();
    await clearTikNetVpnProfiles(container);
    return;
  }

  try {
    await container.read(tikNetApiProvider).getMe(baseUrl: baseUrl, accessToken: token);
    await auth.extendSession();
    // syncAll applies profile; avoid syncAllAndApplyProfile doubling work. VPN kept if config unchanged.
    unawaited(container.read(syncServiceProvider).syncAll());
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      await container.read(connectionNotifierProvider.notifier).abortConnection();
      await auth.logout();
      await clearTikNetVpnProfiles(container);
    }
  } catch (_) {
    // Offline: keep token; user can retry sync from account tab.
  }
}

/// Removes on-disk TikNet VPN profile(s) so a stale config cannot keep routing.
Future<void> clearTikNetVpnProfiles(ProviderContainer container) async {
  try {
    await container.read(connectionNotifierProvider.notifier).abortConnection();
    await container.read(Preferences.startedByUser.notifier).update(false);
    final repo = await container.read(profileRepositoryProvider.future);
    final listResult = await repo.watchAll().first;
    await listResult.fold((_) async {}, (profiles) async {
      for (final p in profiles) {
        if (p.userOverride?.name == tikNetProfileDisplayName || p.name == tikNetProfileDisplayName) {
          await repo.deleteById(p.id, p.active).run();
        }
      }
    });
    await container.read(Preferences.tikNetProfileId.notifier).update('');
  } catch (_) {}
}
