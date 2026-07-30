import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/features/tiknet/service/tiknet_telemetry_service.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/model/tiknet_entitlement.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:hiddify/core/hiddify_remote_block.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'connection_notifier.g.dart';

/// True while TikNet temporarily starts core in proxy mode for urltest (UI stays disconnected).
final tikNetUrlTestProbeActiveProvider = StateProvider<bool>((ref) => false);

/// Prevents stacked auto-restores when coreRestartSignal rebuilds the notifier.
DateTime? _tikNetLastRestoreAttempt;

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  /// While true, UI stays on disconnecting until core reports stopped (avoids CONNECTING loop).
  bool _ignoreCoreUntilStopped = false;

  /// Set when user taps Connect during a urltest probe — probe cleans up then yields.
  bool _urlTestProbeCancel = false;
  Completer<void>? _urlTestProbeDone;

  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (tikNetMode) {
        // Avoid false "reconnect" haptic when resuming app (brief status flicker).
        final freshConnect = switch ((previous, next)) {
          (AsyncData(value: Connecting()), AsyncData(value: Connected())) => true,
          _ => false,
        };
        if (freshConnect) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();
        }
        return;
      }
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      final shouldReconnect = next == null || previous.id != next.id;
      if (!shouldReconnect) return;
      // TikNet: profile id churn during sync must not bounce a live tunnel.
      if (tikNetMode && ref.read(Preferences.startedByUser)) {
        loggy.info("skip profile-id reconnect — TikNet VPN intent active");
        return;
      }
      await reconnect(next);
    });
    ref.watch(coreRestartSignalProvider);

    if (Platform.isAndroid && tikNetMode) {
      Future.microtask(() async {
        if (!ref.read(Preferences.startedByUser)) {
          if (ref.read(tikNetUrlTestProbeActiveProvider)) return;
          // Expired/blocked accounts must not keep a leftover tunnel (incl. catalog).
          if (!_tikNetEntitlementAllowsConnect()) {
            await forceStopForEntitlementBlock();
            return;
          }
          // Never force-stop a live tunnel because of a prefs/status flicker.
          if (await ref.read(hiddifyCoreServiceProvider).adoptRunningVpnSession()) {
            loggy.info("startedByUser=false but VPN live — adopting, not force-stopping");
            return;
          }
          await _forceStopCore();
          return;
        }
        final last = _tikNetLastRestoreAttempt;
        if (last != null && DateTime.now().difference(last) < const Duration(seconds: 8)) {
          return;
        }
        _tikNetLastRestoreAttempt = DateTime.now();
        await restoreVpnSessionIfNeeded();
      });
    }

    yield* _connectionRepo.watchConnectionStatus().map(_mapStatusFromCore).doOnData((event) async {
      if (event case Disconnected()) {
        _ignoreCoreUntilStopped = false;
      }
      if (tikNetMode) {
        final started = ref.read(Preferences.startedByUser);
        if (event is Connected && started) {
          if (ref.read(Preferences.tikNetVpnConnectedAt) == null) {
            await ref.read(Preferences.tikNetVpnConnectedAt.notifier).update(DateTime.now());
          }
        } else if (event is Disconnected && !started) {
          await ref.read(Preferences.tikNetVpnConnectedAt.notifier).update(null);
        }
      }
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
        ref.read(Preferences.startedByUser.notifier).update(false);
      }
      loggy.info("connection status: ${event.format()}");
      if (tikNetMode) {
        TikNetDiagnosticLog.i('vpn', event.format(), {
          'started_by_user': ref.read(Preferences.startedByUser),
          'ignore_core': _ignoreCoreUntilStopped,
        });
      }
    });
  }

  ConnectionStatus _mapStatusFromCore(ConnectionStatus event) {
    if (_ignoreCoreUntilStopped) {
      return switch (event) {
        Disconnected() => event,
        _ => const Disconnecting(),
      };
    }
    // Temporary proxy urltest: core may be Connected but UI must stay Disconnected.
    if (ref.read(tikNetUrlTestProbeActiveProvider)) {
      return switch (event) {
        Connected() || Connecting() || Disconnecting() => const Disconnected(),
        _ => event,
      };
    }
    if (!ref.read(Preferences.startedByUser)) {
      return switch (event) {
        Connected() || Connecting() || Disconnecting() => () {
          unawaited(_forceStopCore());
          return const Disconnected();
        }(),
        _ => event,
      };
    }
    return event;
  }

  /// Runs [action] with sing-box up. If user-connected, runs immediately; otherwise
  /// starts a temporary [ServiceMode.proxy] session (no TUN / no startedByUser) for urltest.
  ///
  /// On iOS, proxy mode may still involve the network extension — we still attempt the probe.
  Future<T> runUrlTestProbe<T>(Future<T> Function() action) async {
    if (tikNetMode && !_tikNetEntitlementAllowsConnect()) {
      throw StateError('urltest probe blocked by entitlement');
    }
    final startedByUser = ref.read(Preferences.startedByUser);
    final uiStatus = state.valueOrNull;
    if (startedByUser && uiStatus is Connected) {
      return action();
    }

    if (_urlTestProbeDone != null && !_urlTestProbeDone!.isCompleted) {
      throw StateError('urltest probe already running');
    }

    _urlTestProbeCancel = false;
    final done = Completer<void>();
    _urlTestProbeDone = done;
    final previousMode = ref.read(ConfigOptions.serviceMode);
    ref.read(tikNetUrlTestProbeActiveProvider.notifier).state = true;
    if (tikNetMode) {
      TikNetDiagnosticLog.i('ping', 'urltest probe start', {'prev_mode': previousMode.key});
    }

    try {
      if (previousMode != ServiceMode.proxy) {
        await ref.read(ConfigOptions.serviceMode.notifier).update(ServiceMode.proxy);
      }
      if (_urlTestProbeCancel || ref.read(Preferences.startedByUser)) {
        throw StateError('urltest probe aborted');
      }

      final activeProfile = await ref.read(activeProfileProvider.future);
      if (activeProfile == null) {
        throw StateError('urltest probe: no active profile');
      }

      // Subscribe before connect so we cannot miss a fast CoreStarted event.
      final coreConnected = Completer<void>();
      final statusSub = _connectionRepo.watchConnectionStatus().listen((s) {
        if (s is Connected && !coreConnected.isCompleted) coreConnected.complete();
      });

      try {
        final connectEither = await _connectionRepo
            .connect(activeProfile, ref.read(Preferences.disableMemoryLimit))
            .run();
        connectEither.fold(
          (err) {
            loggy.warning("urltest probe connect failed", err);
            throw StateError('urltest probe connect failed: $err');
          },
          (_) {},
        );
        if (_urlTestProbeCancel || ref.read(Preferences.startedByUser)) {
          throw StateError('urltest probe aborted');
        }

        await coreConnected.future.timeout(const Duration(seconds: 20));
        if (_urlTestProbeCancel || ref.read(Preferences.startedByUser)) {
          throw StateError('urltest probe aborted');
        }

        return await action();
      } finally {
        await statusSub.cancel();
      }
    } finally {
      final userTookOver = ref.read(Preferences.startedByUser);
      try {
        if (!userTookOver) {
          await _connectionRepo.disconnect().run().timeout(const Duration(seconds: 12));
        }
      } on TimeoutException {
        loggy.warning("urltest probe disconnect timed out");
        if (!userTookOver) await _forceStopCore();
      } catch (e, st) {
        loggy.warning("urltest probe disconnect failed", e, st);
        if (!userTookOver) await _forceStopCore();
      }
      try {
        // Always restore mode even if user took over — otherwise proxy sticks in prefs.
        if (ref.read(ConfigOptions.serviceMode) != previousMode) {
          await ref.read(ConfigOptions.serviceMode.notifier).update(previousMode);
        }
      } catch (e, st) {
        loggy.warning("urltest probe restore serviceMode failed", e, st);
      }
      if (!done.isCompleted) done.complete();
      if (identical(_urlTestProbeDone, done)) _urlTestProbeDone = null;
      ref.read(tikNetUrlTestProbeActiveProvider.notifier).state = false;
      _urlTestProbeCancel = false;
      if (!userTookOver) {
        state = const AsyncData(Disconnected());
      }
      if (tikNetMode) {
        TikNetDiagnosticLog.i('ping', 'urltest probe end', {'user_took_over': userTookOver});
      }
    }
  }

  Future<void> _awaitUrlTestProbeIfActive() async {
    if (!ref.read(tikNetUrlTestProbeActiveProvider) && (_urlTestProbeDone == null || _urlTestProbeDone!.isCompleted)) {
      return;
    }
    _urlTestProbeCancel = true;
    final done = _urlTestProbeDone;
    if (done == null || done.isCompleted) return;
    try {
      // Keep the connect button responsive — never block tens of seconds on probe cleanup.
      await done.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      loggy.warning("waiting for urltest probe timed out — force stop");
      if (tikNetMode) TikNetDiagnosticLog.w('vpn', 'probe wait timeout, force stop');
      await _forceStopCore();
    }
  }

  Future<void> _forceStopCore() async {
    try {
      await ref.read(hiddifyCoreServiceProvider).stop().run();
    } catch (e, st) {
      loggy.warning("force stop core failed", e, st);
    }
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  /// Hard stop used when the account is expired / exhausted / disabled so a
  /// leftover Android VPN (including catalog) cannot keep routing.
  Future<void> forceStopForEntitlementBlock() async {
    await ref.read(Preferences.startedByUser.notifier).update(false);
    if (tikNetMode) {
      await ref.read(Preferences.tikNetVpnConnectedAt.notifier).update(null);
    }
    await abortConnection();
    await _forceStopCore();
    state = const AsyncData(Disconnected());
  }

  Future<void> mayConnect() async {
    if (tikNetMode && !_tikNetEntitlementAllowsConnect()) return;
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  /// After app reopen / process death when user had VPN enabled.
  ///
  /// Do not call this on a normal TikNet resume while the FG channel was kept open —
  /// status briefly flickers to STOPPED and a full reconnect would bounce the tunnel.
  Future<void> restoreVpnSessionIfNeeded() async {
    if (!tikNetMode || !ref.read(Preferences.startedByUser)) return;
    if (!_tikNetEntitlementAllowsConnect()) {
      TikNetDiagnosticLog.w('vpn', 'restore blocked by entitlement');
      await forceStopForEntitlementBlock();
      return;
    }

    final core = ref.read(hiddifyCoreServiceProvider);

    // Prefer adopting an already-running tunnel — never bounce it.
    for (var i = 0; i < 8; i++) {
      if (!ref.read(Preferences.startedByUser)) return;
      if (state case AsyncData(:final value)) {
        if (value is Connected || value is Connecting) return;
      }
      if (await core.adoptRunningVpnSession()) {
        loggy.info("VPN service still running — adopted session without reconnect");
        TikNetDiagnosticLog.i('vpn', 'adopt existing session (no bounce)');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    if (!ref.read(Preferences.startedByUser)) return;
    if (state case AsyncData(:final value)) {
      if (value is Connected || value is Connecting) return;
    }

    loggy.info("restoring VPN session after app open");
    TikNetDiagnosticLog.i('vpn', 'auto-restore after app open');
    await mayConnect();
  }

  Future<void> toggleConnection() async {
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      if (tikNetMode && !_tikNetEntitlementAllowsConnect()) {
        await forceStopForEntitlementBlock();
        return;
      }
      await _awaitUrlTestProbeIfActive();
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          if (tikNetMode && !_tikNetEntitlementAllowsConnect()) {
            await haptic.mediumImpact();
            await forceStopForEntitlementBlock();
            return;
          }
          // Mark user intent first so any active urltest probe aborts immediately.
          await haptic.lightImpact();
          _ignoreCoreUntilStopped = false;
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _awaitUrlTestProbeIfActive();
          await _connect();
        case Connected():
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        case Connecting() || Disconnecting():
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
      }
    }
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (tikNetMode && !_tikNetEntitlementAllowsConnect()) {
      TikNetDiagnosticLog.w('vpn', 'reconnect blocked by entitlement');
      await forceStopForEntitlementBlock();
      return;
    }
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      await ref.read(Preferences.startedByUser.notifier).update(true);
      await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) async {
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        await ref
            .read(dialogNotifierProvider.notifier)
            .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      }).run();
    }
  }

  Future<void> abortConnection({bool preserveUserIntent = false}) async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting() || Disconnecting():
          loggy.debug("aborting connection");
          await _disconnect(preserveUserIntent: preserveUserIntent);
        default:
      }
    }
  }

  final _connectLock = SingleCall();
  final _disconnectLock = SingleCall();

  Future<void> _connect() async {
    await _connectLock.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect is still running, ignoring");
      },
    );
  }

  bool _tikNetEntitlementAllowsConnect() {
    if (!tikNetMode) return true;
    return evaluateTikNetEntitlement(ref.read(syncServiceProvider).getProfile()).allowed;
  }

  Future<void> _connectThrottled() async {
    if (tikNetMode && !_tikNetEntitlementAllowsConnect()) {
      loggy.info("tiknet entitlement blocks connect");
      TikNetDiagnosticLog.w('vpn', 'connect blocked by entitlement');
      await forceStopForEntitlementBlock();
      return;
    }
    // Tunnel already up (app reopen) — never bounce via stop/start.
    if (tikNetMode && await ref.read(hiddifyCoreServiceProvider).adoptRunningVpnSession()) {
      loggy.info("skip connect — VPN already running");
      TikNetDiagnosticLog.i('vpn', 'skip connect; already running');
      return;
    }
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    await _connectionRepo.connect(activeProfile, ref.read(Preferences.disableMemoryLimit)).mapLeft((
      ConnectionFailure err,
    ) async {
      loggy.warning("error connecting", err);
      if (tikNetMode) {
        TikNetDiagnosticLog.e('vpn', 'connect failed', {'error': err.toString()});
      }
      //Go err is not normal object to see the go errors are string and need to be dumped
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      loggy.warning(err);
      if (tikNetMode) {
        ref.read(tikNetTelemetryServiceProvider).reportConnectionError(err, stage: 'connect');
        final msg = err.toString();
        if (msg.contains('starting background core') || msg.contains('startService')) {
          ref.read(tikNetTelemetryServiceProvider).reportVpnCoreStartFailed(message: msg);
        }
      }
      if (!blockHiddifyRemoteServices && err.toString().contains("panic")) {
        await Sentry.captureException(Exception(err.toString()));
      }
      await ref.read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }).run();
  }

  Future<void> _disconnect({bool preserveUserIntent = false}) async {
    _ignoreCoreUntilStopped = true;
    if (!preserveUserIntent) {
      await ref.read(Preferences.startedByUser.notifier).update(false);
      if (tikNetMode) {
        await ref.read(Preferences.tikNetVpnConnectedAt.notifier).update(null);
      }
    }
    state = const AsyncData(Disconnecting());

    await _disconnectLock.run(
      () async {
        try {
          await _disconnectCore().timeout(const Duration(seconds: 12));
        } on TimeoutException {
          loggy.warning("disconnect timed out, forcing stop");
          if (tikNetMode) TikNetDiagnosticLog.w('vpn', 'disconnect timeout, force stop');
          await _forceStopCore();
          state = const AsyncData(Disconnected());
        }
      },
      onIgnored: () {
        loggy.debug("disconnect already running, forcing stop");
        unawaited(_forceStopCore());
        state = const AsyncData(Disconnected());
      },
    );
  }

  Future<void> _disconnectCore() async {
    final either = await _connectionRepo.disconnect().run();
    ConnectionFailure? disconnectErr;
    either.match(
      (l) {
        disconnectErr = l;
      },
      (_) {
      },
    );

    if (disconnectErr != null) {
      loggy.warning("error disconnecting", disconnectErr);
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(disconnectErr!.present(ref.read(translationsProvider).requireValue));
      state = AsyncError(disconnectErr!, StackTrace.current);
      return;
    }

    state = const AsyncData(Disconnected());
    _ignoreCoreUntilStopped = false;
  }
}

@Riverpod(keepAlive: true)
Future<bool> serviceRunning(Ref ref) async {
  // ref.watch(coreRestartSignalProvider);
  return await ref
      .watch(connectionNotifierProvider.selectAsync((data) => data.isConnected))
      .onError((error, stackTrace) => false);
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}
