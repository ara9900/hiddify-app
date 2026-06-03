import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_panel_server_display.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final serverCatalogProvider = FutureProvider<TikNetServerCatalog>((ref) async {
  ref.watch(Preferences.tikNetAccessToken);
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
    var catalog = TikNetServerCatalog.fromJson(data);
    final storedMode = readStoredServerDisplayMode(ref);
    if (catalog.displayMode != storedMode) {
      catalog = TikNetServerCatalog(
        personalAvailable: storedMode == TikNetServerDisplayMode.catalogOnly
            ? false
            : catalog.personalAvailable,
        servers: storedMode == TikNetServerDisplayMode.personalOnly ? const [] : catalog.servers,
        displayMode: storedMode,
      );
    }
    final subUrl = ref.read(Preferences.tikNetSubscriptionUrl);
    final ping = ref.read(tikNetClientPingServiceProvider);
    return ping.measureCatalog(
      catalog,
      personalSubscriptionUrl: subUrl,
    );
  } catch (_) {
    return const TikNetServerCatalog(personalAvailable: false, servers: []);
  }
});

final selectedServerProvider = Provider<TikNetServerSelection>((ref) {
  ref.watch(Preferences.tikNetSelectedServer);
  return parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
});
