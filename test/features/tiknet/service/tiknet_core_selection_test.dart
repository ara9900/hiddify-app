import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/service/tiknet_core_selection.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

OutboundGroup _group(
  String tag, {
  String type = 'selector',
  String selected = '',
  List<String> items = const [],
}) {
  return OutboundGroup(
    tag: tag,
    type: type,
    selected: selected,
    items: [for (final i in items) OutboundInfo(tag: i, urlTestDelay: 0)],
  );
}

void main() {
  group('resolveSelectionGroupTag', () {
    test('picks the live selector that lists the outbound, not the profile tag', () {
      // The profile calls its selector "proxy"; the core rebuilt it as "select".
      final groups = [
        _group('select', items: ['balance', 'lowest', 'node-a', 'node-b']),
        _group('lowest', type: 'balancer', items: ['node-a', 'node-b']),
      ];
      expect(
        resolveSelectionGroupTag(groups: groups, outboundTag: 'node-a', preferred: 'proxy'),
        'select',
      );
    });

    test('honours a preferred tag only when the core confirms it', () {
      final groups = [
        _group('select', items: ['node-a']),
        _group('manual', items: ['node-a']),
      ];
      expect(
        resolveSelectionGroupTag(groups: groups, outboundTag: 'node-a', preferred: 'manual'),
        'manual',
      );
      expect(
        resolveSelectionGroupTag(groups: groups, outboundTag: 'node-a', preferred: 'Select'),
        'select',
      );
    });

    test('never returns a non-selector group', () {
      final groups = [
        _group('auto', type: 'urltest', items: ['node-a']),
        _group('select', items: ['auto']),
      ];
      expect(
        resolveSelectionGroupTag(groups: groups, outboundTag: 'node-a'),
        'select',
      );
    });

    test('falls back to the core literal when no snapshot is available', () {
      expect(
        resolveSelectionGroupTag(groups: const [], outboundTag: 'node-a', preferred: 'proxy'),
        kCoreSelectorTag,
      );
    });
  });

  group('resolveSafeDefaultOutbound', () {
    test('replaces the round-robin balance default with lowest', () {
      final groups = [
        _group('select', selected: kCoreBalanceTag, items: ['balance', 'lowest', 'node-a']),
      ];
      expect(resolveSafeDefaultOutbound(groups), kCoreLowestTag);
    });

    test('leaves an already sane selection alone', () {
      final groups = [
        _group('select', selected: 'node-a', items: ['balance', 'lowest', 'node-a']),
      ];
      expect(resolveSafeDefaultOutbound(groups), isNull);
    });

    test('falls back to auto when the core has no lowest group', () {
      final groups = [
        _group('select', selected: kCoreBalanceTag, items: ['balance', 'auto', 'node-a']),
      ];
      expect(resolveSafeDefaultOutbound(groups), 'auto');
    });

    test('returns null when nothing safe exists', () {
      final groups = [
        _group('select', selected: kCoreBalanceTag, items: ['balance', 'node-a']),
      ];
      expect(resolveSafeDefaultOutbound(groups), isNull);
    });
  });
}
