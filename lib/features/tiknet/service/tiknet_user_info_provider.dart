import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Cached TikNet user info (GET /api/customer/me). Null when not TikNet or not logged in.
/// Used to show subscription expire state on Home without logging the user out.
final tikNetUserInfoProvider = FutureProvider<TikNetUserInfo?>((ref) async {
  if (!tikNetMode) return null;
  final auth = ref.watch(authServiceProvider);
  if (!auth.isLoggedIn()) return null;
  final panelUrl = ref.watch(Preferences.tikNetPanelBaseUrl);
  final token = auth.getToken();
  if (panelUrl.isEmpty || token.isEmpty) return null;
  return ref.read(tikNetApiProvider).getMe(baseUrl: panelUrl, accessToken: token);
});
