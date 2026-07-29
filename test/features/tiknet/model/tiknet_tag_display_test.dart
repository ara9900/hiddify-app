import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';

void main() {
  group('stripHiddifyTagSuffix', () {
    test('removes the core uniqueness marker and trailing index', () {
      expect(stripHiddifyTagSuffix('Germany-1 § 3'), 'Germany-1');
      expect(stripHiddifyTagSuffix('vless http § 5'), 'vless http');
      expect(stripHiddifyTagSuffix('ss § 6'), 'ss');
    });

    test('leaves ordinary names untouched', () {
      expect(stripHiddifyTagSuffix('Germany-1'), 'Germany-1');
      expect(stripHiddifyTagSuffix('vless-alireza'), 'vless-alireza');
    });

    test('displayLabel prefers a clean label over the raw tag', () {
      const node = TikNetPersonalProxyNode(
        tag: 'Germany-1 § 3',
        groupTag: 'select',
        label: 'Germany-1 § 3',
      );
      expect(node.displayLabel, 'Germany-1');
    });
  });
}
