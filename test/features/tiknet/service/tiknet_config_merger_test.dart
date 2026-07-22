import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';

String _subConfig({required List<String> proxyTags}) {
  final outs = <Map<String, dynamic>>[
    {
      'type': 'selector',
      'tag': 'Select',
      'outbounds': [...proxyTags, 'direct'],
      'default': proxyTags.first,
    },
    for (final t in proxyTags)
      {
        'type': 'vless',
        'tag': t,
        'server': 'sub.example.com',
        'server_port': 443,
        'uuid': '00000000-0000-0000-0000-000000000001',
      },
    {'type': 'direct', 'tag': 'direct'},
  ];
  return jsonEncode({'outbounds': outs, 'route': {'final': 'Select'}});
}

String _catalogConfig({required String tag}) {
  return jsonEncode({
    'outbounds': [
      {
        'type': 'vless',
        'tag': tag,
        'server': 'cat.example.com',
        'server_port': 443,
        'uuid': '00000000-0000-0000-0000-000000000002',
      },
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': {'final': tag},
  });
}

TikNetServerEntry _server(int id, String name) => TikNetServerEntry(
      id: id,
      name: name,
      countryCode: 'DE',
      tier: 'free',
      sourceType: 'catalog',
      requiresPaid: false,
      accessible: true,
      sortOrder: 0,
    );

void main() {
  group('mergeTikNetConfigs', () {
    test('merges subscription and catalog into one selector', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: _subConfig(proxyTags: ['de-sub']),
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(7, 'DE Catalog'),
            configBytes: utf8.encode(_catalogConfig(tag: 'proxy')),
          ),
        ],
      );

      expect(merged.isEmpty, isFalse);
      expect(merged.nodes.length, 2);
      expect(merged.nodes.where((n) => n.source == TikNetNodeSource.subscription).length, 1);
      expect(merged.nodes.where((n) => n.source == TikNetNodeSource.catalog).length, 1);

      final cat = merged.nodes.firstWhere((n) => n.isCatalog);
      expect(cat.tag, startsWith('cat-7-'));
      expect(cat.catalogId, 7);
      expect(cat.label, 'DE Catalog');

      final map = jsonDecode(merged.configJson) as Map<String, dynamic>;
      final outs = (map['outbounds'] as List).cast<Map<String, dynamic>>();
      final selector = outs.firstWhere((o) => o['type'] == 'selector' && o['tag'] == 'Select');
      final listed = (selector['outbounds'] as List).map((e) => e.toString()).toList();
      expect(listed, contains('de-sub'));
      expect(listed, contains(cat.tag));
    });

    test('avoids tag collision with unique cat prefixes', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: _subConfig(proxyTags: ['proxy']),
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(1, 'A'),
            configBytes: utf8.encode(_catalogConfig(tag: 'proxy')),
          ),
          TikNetCatalogConfigInput(
            server: _server(2, 'B'),
            configBytes: utf8.encode(_catalogConfig(tag: 'proxy')),
          ),
        ],
      );

      final tags = merged.nodes.map((n) => n.tag).toSet();
      expect(tags.length, merged.nodes.length);
      expect(tags, contains('proxy'));
      expect(tags.any((t) => t.startsWith('cat-1-')), isTrue);
      expect(tags.any((t) => t.startsWith('cat-2-')), isTrue);
    });

    test('catalog-only when subscription empty', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: null,
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(9, 'Fallback'),
            configBytes: utf8.encode(_catalogConfig(tag: 'node')),
          ),
        ],
      );

      expect(merged.nodes.length, 1);
      expect(merged.nodes.first.source, TikNetNodeSource.catalog);
      expect(merged.nodes.first.label, 'Fallback');

      final map = jsonDecode(merged.configJson) as Map<String, dynamic>;
      final outs = (map['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(outs.any((o) => o['type'] == 'selector'), isTrue);
    });

    test('empty when both sources empty', () {
      final merged = mergeTikNetConfigs(subscriptionRaw: null, catalogConfigs: const []);
      expect(merged.isEmpty, isTrue);
      expect(merged.configJson, isEmpty);
    });

    test('skips unparsable catalog config without crashing', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: _subConfig(proxyTags: ['ok']),
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(3, 'Bad'),
            configBytes: utf8.encode('not-json-or-singbox'),
          ),
        ],
      );
      expect(merged.nodes.length, 1);
      expect(merged.nodes.first.tag, 'ok');
    });
  });

  group('resolveCatalogSelectionToNode', () {
    test('maps legacy cat id to merged node', () {
      final catalog = TikNetPersonalOutboundCatalog(
        mainGroupTag: 'Select',
        autoModes: const [],
        nodes: const [
          TikNetPersonalProxyNode(
            tag: 'cat-5-x',
            groupTag: 'Select',
            label: 'X',
            source: TikNetNodeSource.catalog,
            catalogId: 5,
          ),
        ],
      );
      final sel = parseServerSelection('cat:5');
      final node = resolveCatalogSelectionToNode(sel, catalog);
      expect(node?.tag, 'cat-5-x');
    });
  });
}
