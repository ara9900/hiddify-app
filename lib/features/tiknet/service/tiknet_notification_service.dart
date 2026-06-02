import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/tiknet_notification.dart';
import 'package:hiddify/features/tiknet/service/auth_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tikNetInboxProvider = FutureProvider<TikNetInbox>((ref) async {
  final auth = ref.watch(authServiceProvider);
  if (!auth.hasAppSession()) return TikNetInbox.empty;

  final baseUrl = ref.watch(Preferences.tikNetPanelBaseUrl);
  final token = auth.getToken();
  if (baseUrl.isEmpty || token.isEmpty) return TikNetInbox.empty;

  try {
    return await ref.read(tikNetApiProvider).getNotifications(baseUrl: baseUrl, accessToken: token);
  } catch (_) {
    return TikNetInbox.empty;
  }
});

final tikNetUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(tikNetInboxProvider).valueOrNull?.unreadCount ?? 0;
});

Future<void> markTikNetNotificationRead(WidgetRef ref, int notificationId) async {
  final baseUrl = ref.read(Preferences.tikNetPanelBaseUrl);
  final token = ref.read(authServiceProvider).getToken();
  if (baseUrl.isEmpty || token.isEmpty || notificationId <= 0) return;
  try {
    await ref.read(tikNetApiProvider).markNotificationRead(
          baseUrl: baseUrl,
          accessToken: token,
          notificationId: notificationId,
        );
    ref.invalidate(tikNetInboxProvider);
  } catch (_) {}
}
