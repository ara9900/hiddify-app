import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';

void main() {
  group('catalog picker display helpers', () {
    test('showCatalog is true when servers empty but mode allows catalog', () {
      const catalog = TikNetServerCatalog(
        personalAvailable: true,
        servers: [],
        displayMode: TikNetServerDisplayMode.both,
      );
      expect(catalog.showCatalog, isTrue);
      expect(catalog.showPersonal, isTrue);
    });

    test('showCatalog false only for personalOnly mode', () {
      const catalog = TikNetServerCatalog(
        personalAvailable: true,
        servers: [
          TikNetServerEntry(
            id: 1,
            name: 'DE',
            countryCode: 'DE',
            tier: 'free',
            sourceType: 'catalog',
            requiresPaid: false,
            accessible: true,
            sortOrder: 0,
          ),
        ],
        displayMode: TikNetServerDisplayMode.personalOnly,
      );
      expect(catalog.showCatalog, isFalse);
    });

    test('filter keeps cat- nodes when servers list is empty', () {
      const nodes = [
        TikNetPersonalProxyNode(
          tag: 'sub-1',
          groupTag: 'Select',
          label: 'Sub',
          source: TikNetNodeSource.subscription,
        ),
        TikNetPersonalProxyNode(
          tag: 'cat-9-de',
          groupTag: 'Select',
          label: 'Catalog DE',
          source: TikNetNodeSource.catalog,
          catalogId: 9,
        ),
      ];
      final filtered = filterPickerNodesForDisplayMode(nodes, TikNetServerDisplayMode.both);
      expect(filtered.map((n) => n.tag), ['sub-1', 'cat-9-de']);

      final personalOnly = filterPickerNodesForDisplayMode(nodes, TikNetServerDisplayMode.personalOnly);
      expect(personalOnly.map((n) => n.tag), ['sub-1']);

      final catalogOnly = filterPickerNodesForDisplayMode(nodes, TikNetServerDisplayMode.catalogOnly);
      expect(catalogOnly.map((n) => n.tag), ['cat-9-de']);
    });

    test('accessibleCatalogMissingFromMerge adds API rows not in merge', () {
      const servers = [
        TikNetServerEntry(
          id: 1,
          name: 'Merged',
          countryCode: 'DE',
          tier: 'free',
          sourceType: 'catalog',
          requiresPaid: false,
          accessible: true,
          sortOrder: 0,
        ),
        TikNetServerEntry(
          id: 2,
          name: 'Missing',
          countryCode: 'TR',
          tier: 'vip',
          sourceType: 'catalog',
          requiresPaid: true,
          accessible: true,
          sortOrder: 1,
        ),
        TikNetServerEntry(
          id: 3,
          name: 'Locked',
          countryCode: 'US',
          tier: 'vip',
          sourceType: 'catalog',
          requiresPaid: true,
          accessible: false,
          sortOrder: 2,
        ),
      ];
      const nodes = [
        TikNetPersonalProxyNode(
          tag: 'cat-1-de',
          groupTag: 'Select',
          label: 'Merged',
          source: TikNetNodeSource.catalog,
          catalogId: 1,
        ),
      ];
      final missing = accessibleCatalogMissingFromMerge(servers, nodes);
      expect(missing.map((s) => s.id), [2]);
    });
  });
}
