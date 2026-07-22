import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';

void main() {
  group('smart selection encoding', () {
    test('default and smart parse to smartSelection', () {
      expect(parseServerSelection('').personalKind, TikNetPersonalPickKind.smart);
      expect(parseServerSelection('personal').personalKind, TikNetPersonalPickKind.smart);
      expect(parseServerSelection('smart').personalKind, TikNetPersonalPickKind.smart);
      expect(encodeServerSelection(smartSelection()), 'smart');
    });

    test('proxy and catalog round-trip', () {
      final proxy = (
        isPersonal: true,
        catalogId: null,
        personalKind: TikNetPersonalPickKind.proxy,
        personalTag: 'de-1',
        personalGroupTag: 'Select',
      );
      expect(encodeServerSelection(proxy), 'p:n:Select:de-1');
      final parsed = parseServerSelection('p:n:Select:de-1');
      expect(parsed.personalKind, TikNetPersonalPickKind.proxy);
      expect(parsed.personalTag, 'de-1');
      expect(parsed.personalGroupTag, 'Select');

      final cat = parseServerSelection('cat:42');
      expect(cat.isPersonal, isFalse);
      expect(cat.catalogId, 42);
      expect(encodeServerSelection(cat), 'cat:42');
    });

    test('selectionIsSmart / needsOutboundApply', () {
      expect(selectionIsSmart(smartSelection()), isTrue);
      expect(selectionNeedsOutboundApply(smartSelection()), isTrue);
      expect(selectionUsesSubscriptionProfile(smartSelection()), isTrue);
      expect(
        selectionUsesSubscriptionProfile((
          isPersonal: false,
          catalogId: 1,
          personalKind: TikNetPersonalPickKind.defaultAuto,
          personalTag: null,
          personalGroupTag: null,
        )),
        isTrue,
      );
      expect(
        selectionNeedsOutboundApply((
          isPersonal: false,
          catalogId: 1,
          personalKind: TikNetPersonalPickKind.defaultAuto,
          personalTag: null,
          personalGroupTag: null,
        )),
        isTrue,
      );
    });
  });
}
