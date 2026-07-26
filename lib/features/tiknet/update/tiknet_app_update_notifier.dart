import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/model/tiknet_app_update_info.dart';
import 'package:hiddify/features/tiknet/service/tiknet_app_update_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_telemetry_service.dart';
import 'package:hiddify/features/tiknet/update/tiknet_apk_installer.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

sealed class TikNetAppUpdateUiState {
  const TikNetAppUpdateUiState();
}

class TikNetAppUpdateIdle extends TikNetAppUpdateUiState {
  const TikNetAppUpdateIdle();
}

class TikNetAppUpdateChecking extends TikNetAppUpdateUiState {
  const TikNetAppUpdateChecking({this.previousInfo});
  final TikNetAppUpdateInfo? previousInfo;
}

class TikNetAppUpdateUpToDate extends TikNetAppUpdateUiState {
  const TikNetAppUpdateUpToDate();
}

class TikNetAppUpdateAvailable extends TikNetAppUpdateUiState {
  const TikNetAppUpdateAvailable(this.info);
  final TikNetAppUpdateInfo info;
}

class TikNetAppUpdateDownloading extends TikNetAppUpdateUiState {
  const TikNetAppUpdateDownloading(this.info, this.progress);
  final TikNetAppUpdateInfo info;
  final double progress;
}

class TikNetAppUpdateError extends TikNetAppUpdateUiState {
  const TikNetAppUpdateError(this.message, {this.info});
  final String message;
  final TikNetAppUpdateInfo? info;
}

final tikNetAppUpdateNotifierProvider =
    NotifierProvider<TikNetAppUpdateNotifier, TikNetAppUpdateUiState>(TikNetAppUpdateNotifier.new);

class TikNetAppUpdateNotifier extends Notifier<TikNetAppUpdateUiState> {
  @override
  TikNetAppUpdateUiState build() => const TikNetAppUpdateIdle();

  int get _installedVersionCode {
    final build = ref.read(appInfoProvider).valueOrNull?.buildNumber ?? '0';
    return int.tryParse(build) ?? 0;
  }

  TikNetAppUpdateInfo? get _infoFromState => switch (state) {
        TikNetAppUpdateAvailable(:final info) => info,
        TikNetAppUpdateDownloading(:final info) => info,
        TikNetAppUpdateError(:final info) => info,
        TikNetAppUpdateChecking(:final previousInfo) => previousInfo,
        _ => null,
      };

  Future<void> checkForUpdate({bool forceRefresh = false}) async {
    if (state is TikNetAppUpdateChecking || state is TikNetAppUpdateDownloading) return;
    final previous = _infoFromState;
    state = TikNetAppUpdateChecking(previousInfo: previous);
    try {
      final info = await ref.read(tikNetAppUpdateServiceProvider).fetchUpdateInfo();
      if (!info.enabled || info.versionCode <= _installedVersionCode) {
        state = const TikNetAppUpdateUpToDate();
        return;
      }
      // Optional dismiss is session-only; every cold start shows again while outdated.
      state = TikNetAppUpdateAvailable(info);
    } catch (e) {
      state = TikNetAppUpdateError('بررسی آپدیت ناموفق بود', info: previous);
    }
  }

  Future<void> dismissOptional(TikNetAppUpdateInfo info) async {
    // Clear any legacy persisted snooze so older installs prompt again next launch.
    final ignored = ref.read(Preferences.tikNetIgnoredUpdateVersionCode);
    if (ignored.isNotEmpty) {
      await ref.read(Preferences.tikNetIgnoredUpdateVersionCode.notifier).update('');
    }
    ref.read(tikNetTelemetryServiceProvider).send('update_dismissed', payload: {'version_code': info.versionCode});
    state = const TikNetAppUpdateUpToDate();
  }

  Future<void> downloadAndInstall(TikNetAppUpdateInfo info) async {
    state = TikNetAppUpdateDownloading(info, 0);
    try {
      final path = await ref.read(tikNetAppUpdateServiceProvider).downloadApk(
            info,
            onProgress: (p) {
              if (state is TikNetAppUpdateDownloading) {
                state = TikNetAppUpdateDownloading(info, p.clamp(0.0, 1.0));
              }
            },
          );
      await TikNetApkInstaller.install(path);
      // System installer is fire-and-forget; keep prompt (esp. force) until real upgrade.
      state = TikNetAppUpdateAvailable(info);
    } catch (e) {
      state = TikNetAppUpdateError(
        e.toString().contains('امنیتی') ? e.toString() : 'دانلود یا نصب ناموفق بود',
        info: info,
      );
    }
  }

  bool get isBlocking {
    final s = state;
    if (s is TikNetAppUpdateAvailable && s.info.force) return true;
    if (s is TikNetAppUpdateDownloading && s.info.force) return true;
    if (s is TikNetAppUpdateError && s.info?.force == true) return true;
    if (s is TikNetAppUpdateChecking && s.previousInfo?.force == true) return true;
    return false;
  }
}
