import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app/widget/app.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';

import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/features/tiknet/service/tiknet_session_guard.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/riverpod_observer.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> lazyBootstrap(WidgetsBinding widgetsBinding, Environment env) async {
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  LoggerController.preInit();
  FlutterError.onError = Logger.logFlutterError;
  WidgetsBinding.instance.platformDispatcher.onError = Logger.logPlatformDispatcherError;

  final stopWatch = Stopwatch()..start();

  final container = ProviderContainer(overrides: [environmentProvider.overrideWithValue(env)]);

  await _init("directories", () => container.read(appDirectoriesProvider.future));
  LoggerController.init(container.read(logPathResolverProvider).appFile().path);

  final appInfo = await _init("app info", () => container.read(appInfoProvider.future));
  await _init("preferences", () => container.read(sharedPreferencesProvider.future));

  if (tikNetMode && !container.read(Preferences.introCompleted)) {
    await container.read(Preferences.introCompleted.notifier).update(true);
  }

  if (!tikNetMode) {
    final enableAnalytics = await container.read(analyticsControllerProvider.future);
    if (enableAnalytics) {
      await _init("analytics", () => container.read(analyticsControllerProvider.notifier).enableAnalytics());
    }
  } else {
    await container.read(sharedPreferencesProvider).requireValue.setBool('enable_analytics', false);
  }

  await _init("preferences migration", () async {
    try {
      await PreferencesMigration(sharedPreferences: container.read(sharedPreferencesProvider).requireValue).migrate();
    } catch (e, stackTrace) {
      Logger.bootstrap.error("preferences migration failed", e, stackTrace);
      if (env == Environment.dev) rethrow;
      Logger.bootstrap.info("clearing preferences");
      await container.read(sharedPreferencesProvider).requireValue.clear();
    }
  });

  if (tikNetMode) {
    await _init("tiknet diagnostic log", () async {
      final dirs = await container.read(appDirectoriesProvider.future);
      TikNetDiagnosticLog.init(dirs.workingDir);
    });
    // Bypass IR IPs/domains via core remote rule-sets (geoip-ir / geosite-ir).
    await _init("tiknet region ir", () async {
      if (container.read(ConfigOptions.region) != Region.ir) {
        await container.read(ConfigOptions.region.notifier).update(Region.ir);
      }
    });
    // One-shot Reality-safe defaults (mux/TLS tricks off; enable Xray conversion when AAR is patched).
    await _init("tiknet reality-safe defaults", () async {
      final prefs = container.read(sharedPreferencesProvider).requireValue;
      if (prefs.getBool('tiknet_reality_defaults_v1') == true) return;
      await container.read(ConfigOptions.enableMux.notifier).update(false);
      await container.read(ConfigOptions.enableTlsFragment.notifier).update(false);
      await container.read(ConfigOptions.enableTlsMixedSniCase.notifier).update(false);
      await container.read(ConfigOptions.enableTlsPadding.notifier).update(false);
      await container.read(ConfigOptions.useXrayCoreWhenPossible.notifier).update(true);
      await prefs.setBool('tiknet_reality_defaults_v1', true);
    });
    // Migrate stored Apple captive urltest URL → gstatic (panel ping_test_url can still override later).
    await _init("tiknet connection test url", () async {
      final current = container.read(ConfigOptions.connectionTestUrl);
      if (current == ConfigOptions.legacyAppleCaptiveTestUrl) {
        await container
            .read(ConfigOptions.connectionTestUrl.notifier)
            .update(ConfigOptions.tikNetDefaultConnectionTestUrl);
      }
    });
    await _init("tiknet session", () => reconcileTikNetSession(container));
  }

  final debug = container.read(debugModeNotifierProvider) || kDebugMode;

  if (PlatformUtils.isDesktop) {
    await _init("window controller", () => container.read(windowNotifierProvider.future));

    final silentStart = container.read(Preferences.silentStart);
    Logger.bootstrap.debug("silent start [${silentStart ? "Enabled" : "Disabled"}]");
    if (!silentStart) {
      await container.read(windowNotifierProvider.notifier).show(focus: false);
    } else {
      Logger.bootstrap.debug("silent start, remain hidden accessible via tray");
    }
    await _init("auto start service", () => container.read(autoStartNotifierProvider.future));
  }
  await _init("logs repository", () => container.read(logRepositoryProvider.future));
  await _init("logger controller", () => LoggerController.postInit(debug));

  Logger.bootstrap.info(appInfo.format());

  await _init("profile repository", () => container.read(profileRepositoryProvider.future));

  await _init("translations", () => container.read(translationsProvider.future));

  await _safeInit("active profile", () => container.read(activeProfileProvider.future), timeout: 1000);
  await _init("hiddify-core", () => container.read(hiddifyCoreServiceProvider).init());

  if (!kIsWeb) {
    if (PlatformUtils.isDesktop) {
      await _safeInit("system tray", () => container.read(systemTrayNotifierProvider.future), timeout: 1000);
    }

    if (PlatformUtils.isAndroid) {
      await _safeInit("android display mode", () async {
        await FlutterDisplayMode.setHighRefreshRate();
      });
    }
  }

  Logger.bootstrap.info("bootstrap took [${stopWatch.elapsedMilliseconds}ms]");
  stopWatch.stop();

  runApp(
    ProviderScope(
      parent: container,
      observers: [RiverpodObserver()],
      child: tikNetMode ? const App() : SentryUserInteractionWidget(child: const App()),
    ),
  );

  // Remove native splash as soon as Flutter paints — no cinematic overlay delay.
  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }
}

Future<T> _init<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  final stopWatch = Stopwatch()..start();
  Logger.bootstrap.info("initializing [$name]");
  Future<T> func() => timeout != null ? initializer().timeout(Duration(milliseconds: timeout)) : initializer();
  try {
    final result = await func();
    Logger.bootstrap.debug("[$name] initialized in ${stopWatch.elapsedMilliseconds}ms");
    return result;
  } catch (e, stackTrace) {
    Logger.bootstrap.error("[$name] error initializing", e, stackTrace);
    rethrow;
  } finally {
    stopWatch.stop();
  }
}

Future<T?> _safeInit<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  try {
    return await _init(name, initializer, timeout: timeout);
  } catch (e) {
    return null;
  }
}
