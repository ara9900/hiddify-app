import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/warp_option/warp_option_notifier.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);
}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
  });

  final Ref ref;

  final Directories directories;
  final HiddifyCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    return singbox.watchStatus().map(
      (event) => switch (event) {
        CoreStopped() => Disconnected(event.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
      },
    );
  }

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) => setup().flatMap(
    (_) => applyConfigOption(activeProfile).flatMap(
      (_) => _startWithSanitizedProfile(activeProfile, disableMemoryLimit, restart: false),
    ),
  );

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      applyConfigOption(activeProfile).flatMap(
        (_) => _startWithSanitizedProfile(activeProfile, disableMemoryLimit, restart: true),
      );

  /// Ensure empty ray2sing WG noise is stripped before the core starts.
  ///
  /// The Go generator re-injects empty `noise.fake_packet` onto WireGuard
  /// endpoints even from a clean profile. We generate → sanitize → start from
  /// that runtime file so the live tunnel does not carry the placeholder.
  TaskEither<ConnectionFailure, Unit> _startWithSanitizedProfile(
    ProfileEntity activeProfile,
    bool disableMemoryLimit, {
    required bool restart,
  }) {
    final profileFile = profilePathResolver.file(activeProfile.id);
    final profilePath = profileFile.path;

    return TaskEither(() async {
      var path = profilePath;
      if (tikNetMode) {
        try {
          if (profileFile.existsSync()) {
            final raw = await profileFile.readAsString();
            final cleaned = sanitizeTikNetSingboxJson(raw);
            if (cleaned != raw) {
              await profileFile.writeAsString(cleaned);
              loggy.debug("stripped empty WireGuard noise from profile before start");
            }
          }
          final generated = await singbox.generateFullConfigByPath(profilePath).run();
          await generated.match(
            (err) async {
              loggy.warning("tiknet pre-start generate failed, using profile path", err);
            },
            (raw) async {
              final cleaned = sanitizeTikNetSingboxJson(raw);
              final runtime = profilePathResolver.file('tiknet-runtime-active');
              await runtime.writeAsString(cleaned);
              path = runtime.path;
            },
          );
        } catch (e, st) {
          loggy.warning("tiknet pre-start sanitize failed", e, st);
          path = profilePath;
        }
      }

      final either = restart
          ? await singbox.restart(path, activeProfile.name, disableMemoryLimit).run()
          : await singbox.start(path, activeProfile.name, disableMemoryLimit).run();
      return either.mapLeft((l) => l is ConnectionFailure ? l : UnexpectedConnectionFailure(l));
    });
  }

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride))
          .mapLeft((l) => ConnectionFailure.invalidConfigOption(null, l))
          .flatMap(
            (overridedOptions) => TaskEither.tryCatch(() async {
              final isWarpLicenseAgreed = ref.read(warpLicenseNotifierProvider);
              final isWarpEnabled = overridedOptions.warp.enable || overridedOptions.warp2.enable;
              if (!isWarpLicenseAgreed && isWarpEnabled) {
                final isAgreed = await ref.read(dialogNotifierProvider.notifier).showWarpLicense();
                if (isAgreed == true) {
                  await ref.read(warpLicenseNotifierProvider.notifier).agree();
                  // return (await applyConfigOption(prof).run()).match((l) => throw l, (_) => unit);
                } else {
                  throw const MissingWarpLicense();
                }
              }
              _configOptionsSnapshot = overridedOptions;
              await singbox.changeOptions(overridedOptions).run();
              return unit;
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st)),
          );
}
