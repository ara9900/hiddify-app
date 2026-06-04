import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Live connection duration while VPN is connected.
final tiknetConnectionUptimeProvider = StreamProvider<String?>((ref) async* {
  ref.watch(connectionNotifierProvider);
  bool connected() => switch (ref.read(connectionNotifierProvider)) {
        AsyncData<ConnectionStatus>(value: Connected()) => true,
        _ => false,
      };
  if (!connected()) {
    yield null;
    return;
  }

  final start = DateTime.now();
  while (connected()) {
    final elapsed = DateTime.now().difference(start);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    final text = h > 0
        ? '${toPersianDigits('$h')}:${toPersianDigits(m.toString().padLeft(2, '0'))}:${toPersianDigits(s.toString().padLeft(2, '0'))}'
        : '${toPersianDigits('$m')}:${toPersianDigits(s.toString().padLeft(2, '0'))}';
    yield text;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  yield null;
});
