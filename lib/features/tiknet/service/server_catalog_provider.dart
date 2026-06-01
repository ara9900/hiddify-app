import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
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
    final data = await ref.read(tikNetApiProvider).getServerCatalog(baseUrl: baseUrl, accessToken: token);
    return TikNetServerCatalog.fromJson(data);
  } catch (_) {
    return const TikNetServerCatalog(personalAvailable: false, servers: []);
  }
});

final selectedServerProvider = Provider<TikNetServerSelection>((ref) {
  ref.watch(Preferences.tikNetSelectedServer);
  return parseServerSelection(ref.read(Preferences.tikNetSelectedServer));
});
