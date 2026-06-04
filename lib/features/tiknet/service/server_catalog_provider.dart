import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_ping_settings.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_server_display.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final serverCatalogProvider = FutureProvider<TikNetServerCatalog>((ref) async {
  ref.watch(Preferences.tikNetAccessToken);
  ref.watch(Preferences.tikNetServerDisplayMode);
  final auth = ref.read(authServiceProvider);
  if (!auth.hasAppSession()) {
    return const TikNetServerCatalog(personalAvailable: false, servers: []);
  }
  final baseUrl = ref.read(Preferences.tikNetPanelBaseUrl);
  final token = auth.getToken();
  if (baseUrl.isEmpty || token.isEmpty) {
    return const TikNetServerCatalog(personalAvailable: false, servers: []);
  }
  try {
    final api = ref.read(tikNetApiProvider);
    final data = await api.getServerCatalog(baseUrl: baseUrl, accessToken: token);
    var modeRaw = (data['display_mode'] as String?)?.trim();
    if (modeRaw == null || modeRaw.isEmpty) {
      try {
        final appConfig = await api.getAppConfig(baseUrl: baseUrl, accessToken: token);
        final serverDisplay = appConfig['server_display'];
        if (serverDisplay is Map) {
          await applyPanelServerDisplaySettings(ref, Map<String, dynamic>.from(serverDisplay));
        }
        await applyPanelPingSettingsFromAppConfig(ref, appConfig);
        modeRaw = ref.read(Preferences.tikNetServerDisplayMode);
      } catch (_) {}
    }
    if (modeRaw != null && modeRaw.isNotEmpty) {
      final current = ref.read(Preferences.tikNetServerDisplayMode);
      if (current != modeRaw) {
        await ref.read(Preferences.tikNetServerDisplayMode.notifier).update(modeRaw);
      }
    }
    final effectiveModeRaw = (modeRaw != null && modeRaw.isNotEmpty)
        ? modeRaw
        : ref.read(Preferences.tikNetServerDisplayMode);
    final mode = TikNetServerDisplayMode.fromApi(effectiveModeRaw);
    var catalog = TikNetServerCatalog.fromJson(data);
    catalog = TikNetServerCatalog(
      personalAvailable: mode == TikNetServerDisplayMode.catalogOnly ? false : catalog.personalAvailable,
      servers: mode == TikNetServerDisplayMode.personalOnly ? const [] : catalog.servers,
      personalPing: catalog.personalPing,
      displayMode: mode,
    );
    return ref.read(tikNetClientPingServiceProvider).catalogWithoutClientPing(catalog);
  } catch (_) {
    return const TikNetServerCatalog(personalAvailable: false, servers: []);
  }
});

final selectedServerProvider = Provider<TikNetServerSelection>((ref) {
  ref.watch(Preferences.tikNetSelectedServer);
  return parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
});
