import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Cached TikNet user info. Uses local sync cache first (no network on every home rebuild).
final tikNetUserInfoProvider = Provider<TikNetUserInfo?>((ref) {
  if (!tikNetMode) return null;
  final auth = ref.watch(authServiceProvider);
  if (!auth.isLoggedIn()) return null;
  ref.watch(Preferences.tikNetCachedProfile);
  return ref.read(syncServiceProvider).getProfile();
});
