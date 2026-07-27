import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/stats/data/stats_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:rxdart/rxdart.dart';

/// Lightweight stats for TikNet connection UI — one gRPC stream, UI updates at most every 2s.
final tiknetConnectionStatsProvider = StreamProvider<TikNetConnectionStats?>((ref) async* {
  final running = await ref.watch(serviceRunningProvider.future);
  if (!running) {
    yield null;
    return;
  }

  final repo = ref.read(statsRepositoryProvider);

  yield* repo
      .watchStats()
      .map((event) => event.getOrElse((_) => SystemInfo.create()))
      .throttleTime(const Duration(seconds: 2), leading: true, trailing: true)
      .map(
        (info) => TikNetConnectionStats(
          uplink: info.uplink.toInt(),
          downlink: info.downlink.toInt(),
          uplinkTotal: info.uplinkTotal.toInt(),
          downlinkTotal: info.downlinkTotal.toInt(),
          memory: info.memory.toInt(),
          connectionsIn: info.connectionsIn,
          connectionsOut: info.connectionsOut,
          outboundTag: info.currentOutbound,
        ),
      );
});

class TikNetConnectionStats {
  const TikNetConnectionStats({
    required this.uplink,
    required this.downlink,
    required this.uplinkTotal,
    required this.downlinkTotal,
    required this.memory,
    required this.connectionsIn,
    required this.connectionsOut,
    required this.outboundTag,
  });

  final int uplink;
  final int downlink;
  final int uplinkTotal;
  final int downlinkTotal;
  final int memory;
  final int connectionsIn;
  final int connectionsOut;
  final String outboundTag;
}
