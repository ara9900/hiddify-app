import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'general_preferences.g.dart';

bool _debugIntroPage = false;

abstract class Preferences {
  static final introCompleted = PreferencesNotifier.create(
    "intro_completed",
    false,
    overrideValue: _debugIntroPage && kDebugMode ? false : null,
  );

  // Null means that auto selection has not been performed yet.
  static final autoAppsSelectionRegion = PreferencesNotifier.create<Region?, String?>(
    "auto_apps_selection_region",
    null,
    mapFrom: (value) => value == null || value.isEmpty ? null : Region.values.byName(value),
    mapTo: (value) => value == null ? '' : value.name,
  );

  static final autoAppsSelectionUpdateInterval = PreferencesNotifier.create<double, double>(
    "auto_apps_selection_update_interval",
    1.0,
  );

  static final autoAppsSelectionLastUpdate = PreferencesNotifier.create<DateTime?, String?>(
    "auto_apps_selection_last_update",
    null,
    mapFrom: (value) => value == null ? null : DateTime.tryParse(value),
    mapTo: (value) => value?.toIso8601String(),
  );

  static final includeApps = PreferencesNotifier.create<List<String>, List<String>>(
    "per_app_proxy_include_list",
    <String>[],
  );

  static final excludeApps = PreferencesNotifier.create<List<String>, List<String>>(
    "per_app_proxy_exclude_list",
    <String>[],
  );

  static final windowMaximized = PreferencesNotifier.create<bool, bool>("window_maximized", false);

  static final windowPosition = PreferencesNotifier.create<Offset?, String?>(
    "window_position",
    null,
    mapFrom: (value) {
      if (value == null) return null;
      final list = value.split(',').map((e) => double.tryParse(e)).toList();
      return Offset(list[0]!, list[1]!);
    },
    mapTo: (value) {
      if (value == null) return null;
      return "${value.dx},${value.dy}";
    },
  );

  static final windowSize = PreferencesNotifier.create<Size, String>(
    "window_size",
    defaultWindowSize,
    mapFrom: (value) {
      final list = value.split(',').map((e) => double.tryParse(e)).toList();
      return Size(list[0]!, list[1]!);
    },
    mapTo: (value) => "${value.width},${value.height}",
  );

  static final silentStart = PreferencesNotifier.create<bool, bool>("silent_start", false);

  static final disableMemoryLimit = PreferencesNotifier.create<bool, bool>(
    "disable_memory_limit",
    // disable memory limit on desktop by default
    PlatformUtils.isDesktop,
  );

  static final perAppProxyMode = PreferencesNotifier.create<PerAppProxyMode, String>(
    "per_app_proxy_mode",
    PerAppProxyMode.off,
    mapFrom: PerAppProxyMode.values.byName,
    mapTo: (value) => value.name,
  );

  static final markNewProfileActive = PreferencesNotifier.create<bool, bool>("mark_new_profile_active", true);

  static final dynamicNotification = PreferencesNotifier.create<bool, bool>("dynamic_notification", true);

  static final autoCheckIp = PreferencesNotifier.create<bool, bool>("auto_check_ip", true);

  static final startedByUser = PreferencesNotifier.create<bool, bool>("started_by_user", false);

  static final storeReviewedByUser = PreferencesNotifier.create<bool, bool>("store_reviewed_by_user", false);

  static final actionAtClose = PreferencesNotifier.create<ActionsAtClosing, String>(
    "action_at_close",
    ActionsAtClosing.ask,
    mapFrom: ActionsAtClosing.values.byName,
    mapTo: (value) => value.name,
  );

  /// TikNet: panel API base URL (e.g. https://panel.example.com)
  static final tikNetPanelBaseUrl = PreferencesNotifier.create<String, String>("tiknet_panel_base_url", "");
  /// TikNet: JWT access token after login
  static final tikNetAccessToken = PreferencesNotifier.create<String, String>("tiknet_access_token", "");
  /// TikNet: token expiry time (stored as ISO 8601 string)
  static final tikNetTokenExpiresAt = PreferencesNotifier.create<DateTime?, String>(
    "tiknet_token_expires_at",
    null,
    mapFrom: (value) => value == null || value.isEmpty ? null : DateTime.tryParse(value),
    mapTo: (value) => value?.toIso8601String() ?? '',
  );
  /// TikNet: subscription URL from login response (may be null)
  static final tikNetSubscriptionUrl = PreferencesNotifier.create<String, String>("tiknet_subscription_url", "");
  /// TikNet: cached profile JSON from GET /api/customer/me
  static final tikNetCachedProfile = PreferencesNotifier.create<String, String>("tiknet_cached_profile", "");
  /// TikNet: cached config (base64) from GET /api/customer/subscription/config
  static final tikNetCachedConfig = PreferencesNotifier.create<String, String>("tiknet_cached_config", "");
  /// TikNet: last successful sync time (ISO 8601)
  static final tikNetLastSyncTime = PreferencesNotifier.create<DateTime?, String>(
    "tiknet_last_sync_time",
    null,
    mapFrom: (value) => value == null || value.isEmpty ? null : DateTime.tryParse(value),
    mapTo: (value) => value?.toIso8601String() ?? '',
  );
  /// TikNet: آخرین پیام اعلان (JSON با message.show, message.type, message.text)
  static final tikNetCachedAnnouncement = PreferencesNotifier.create<String, String>("tiknet_cached_announcement", "");
}

@Riverpod(keepAlive: true)
class DebugModeNotifier extends _$DebugModeNotifier {
  late final _pref = PreferencesEntry(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "debug_mode",
    defaultValue: ref.read(environmentProvider) == Environment.dev,
  );

  @override
  bool build() => _pref.read();

  Future<void> update(bool value) {
    state = value;
    return _pref.write(value);
  }
}
