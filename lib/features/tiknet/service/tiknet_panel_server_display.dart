import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _allowedModes = {'both', 'personal_only', 'catalog_only'};

/// Apply [server_display] from GET /api/customer/app-config.
Future<void> applyPanelServerDisplaySettings(Ref ref, Map<String, dynamic>? serverDisplay) async {
  if (serverDisplay == null) return;
  final modeRaw = (serverDisplay['mode'] as String?)?.trim().toLowerCase() ?? '';
  if (!_allowedModes.contains(modeRaw)) return;
  final current = ref.read(Preferences.tikNetServerDisplayMode);
  if (current != modeRaw) {
    await ref.read(Preferences.tikNetServerDisplayMode.notifier).update(modeRaw);
  }
}

TikNetServerDisplayMode readStoredServerDisplayMode(Ref ref) {
  return TikNetServerDisplayMode.fromApi(ref.read(Preferences.tikNetServerDisplayMode));
}
