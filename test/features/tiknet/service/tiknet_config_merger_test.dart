import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_config_merger.dart';

String _subConfig({required List<String> proxyTags, bool withUrltest = false}) {
  final outs = <Map<String, dynamic>>[
    {
      'type': 'selector',
      'tag': 'Select',
      'outbounds': [
        if (withUrltest) 'auto',
        ...proxyTags,
        'direct',
      ],
      'default': withUrltest ? 'auto' : proxyTags.first,
    },
    if (withUrltest)
      {
        'type': 'urltest',
        'tag': 'auto',
        // Intentionally subscription-only — merger must add catalog leaves.
        'outbounds': [...proxyTags],
        'url': 'https://www.gstatic.com/generate_204',
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

    test('adds catalog tags to existing urltest group for ping', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: _subConfig(proxyTags: ['de-sub'], withUrltest: true),
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(7, 'DE Catalog'),
            configBytes: utf8.encode(_catalogConfig(tag: 'proxy')),
          ),
        ],
      );

      final cat = merged.nodes.firstWhere((n) => n.isCatalog);
      final map = jsonDecode(merged.configJson) as Map<String, dynamic>;
      final outs = (map['outbounds'] as List).cast<Map<String, dynamic>>();
      final auto = outs.firstWhere((o) => o['type'] == 'urltest' && o['tag'] == 'auto');
      final listed = (auto['outbounds'] as List).map((e) => e.toString()).toList();
      expect(listed, contains('de-sub'));
      expect(listed, contains(cat.tag));
    });

    test('creates auto urltest with all leaf tags when missing', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: _subConfig(proxyTags: ['de-sub']),
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(7, 'DE Catalog'),
            configBytes: utf8.encode(_catalogConfig(tag: 'proxy')),
          ),
        ],
      );

      final cat = merged.nodes.firstWhere((n) => n.isCatalog);
      final map = jsonDecode(merged.configJson) as Map<String, dynamic>;
      final outs = (map['outbounds'] as List).cast<Map<String, dynamic>>();
      final autos = outs.where((o) => o['type'] == 'urltest').toList();
      expect(autos, isNotEmpty);
      final listed = (autos.first['outbounds'] as List).map((e) => e.toString()).toList();
      expect(listed, contains('de-sub'));
      expect(listed, contains(cat.tag));
      final selector = outs.firstWhere((o) => o['type'] == 'selector');
      final selListed = (selector['outbounds'] as List).map((e) => e.toString()).toList();
      expect(selListed, contains('auto'));
    });

    test('drops panel banner outbounds and their group references', () {
      final raw = jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'Select',
            'outbounds': ['banner', 'de-sub', 'direct'],
          },
          {
            'type': 'urltest',
            'tag': 'auto',
            'outbounds': ['banner', 'de-sub'],
          },
          // Panel info banner: display-only, but a dialable outbound to the core.
          {
            'type': 'vless',
            'tag': 'banner',
            'server': '0.0.0.0',
            'server_port': 1234,
            'uuid': '00000000-0000-0000-0000-000000000003',
          },
          {
            'type': 'vless',
            'tag': 'de-sub',
            'server': 'sub.example.com',
            'server_port': 443,
            'uuid': '00000000-0000-0000-0000-000000000001',
          },
          {'type': 'direct', 'tag': 'direct'},
        ],
        'route': {'final': 'Select'},
      });

      final merged = mergeTikNetConfigs(subscriptionRaw: raw);

      expect(merged.nodes.map((n) => n.tag), isNot(contains('banner')));
      expect(merged.nodes.map((n) => n.tag), contains('de-sub'));

      final map = jsonDecode(merged.configJson) as Map<String, dynamic>;
      final outs = (map['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(outs.any((o) => o['tag'] == 'banner'), isFalse);
      for (final o in outs) {
        final refs = o['outbounds'];
        if (refs is List) {
          expect(refs.map((e) => e.toString()), isNot(contains('banner')));
        }
      }
    });
  });

  group('wireguard endpoints', () {
    test('merge keeps endpoints and adds them to selector', () {
      final sub = jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'select',
            'outbounds': ['vless-1'],
          },
          {
            'type': 'vless',
            'tag': 'vless-1',
            'server': 'de.example.com',
            'server_port': 443,
          },
          {'type': 'direct', 'tag': 'direct'},
        ],
        'endpoints': [
          {
            'type': 'wireguard',
            'tag': 'WG § 5',
            'address': '10.0.0.9/32',
            'peers': [
              {'address': '31.216.62.129', 'port': 443},
            ],
          },
        ],
        'route': {'final': 'select'},
      });
      final merged = mergeTikNetConfigs(subscriptionRaw: sub, catalogConfigs: const []);
      expect(merged.nodes.map((n) => n.tag), containsAll(['vless-1', 'WG § 5']));
      final map = jsonDecode(merged.configJson) as Map<String, dynamic>;
      final endpoints = (map['endpoints'] as List).cast<Map<String, dynamic>>();
      expect(endpoints.any((e) => e['tag'] == 'WG § 5'), isTrue);
      final select = (map['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((o) => o['type'] == 'selector');
      expect((select['outbounds'] as List).map((e) => e.toString()), contains('WG § 5'));
    });
  });

  group('isUnroutableOutbound', () {
    test('flags placeholder servers and bad ports', () {
      expect(isUnroutableOutbound({'type': 'vless', 'server': '0.0.0.0', 'server_port': 1234}), isTrue);
      expect(isUnroutableOutbound({'type': 'vless', 'server': '127.0.0.1', 'server_port': 8080}), isTrue);
      expect(isUnroutableOutbound({'type': 'vless', 'server': 'ok.example.com', 'server_port': 0}), isTrue);
      expect(isUnroutableOutbound({'type': 'vless'}), isTrue);
    });

    test('keeps real proxies and never touches group or utility outbounds', () {
      expect(isUnroutableOutbound({'type': 'vless', 'server': 'ok.example.com', 'server_port': 443}), isFalse);
      expect(isUnroutableOutbound({'type': 'direct', 'tag': 'direct'}), isFalse);
      expect(isUnroutableOutbound({'type': 'selector', 'tag': 'Select'}), isFalse);
      // WireGuard style: no top-level server, peers carry the endpoints.
      expect(
        isUnroutableOutbound({
          'type': 'wireguard',
          'peers': [
            {'server': 'wg.example.com', 'server_port': 51820},
          ],
        }),
        isFalse,
      );
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

  group('stripCatalogOutboundsFromConfig', () {
    test('removes cat-{id}- leaves and cleans selector/urltest refs', () {
      final merged = mergeTikNetConfigs(
        subscriptionRaw: _subConfig(proxyTags: ['de-sub'], withUrltest: true),
        catalogConfigs: [
          TikNetCatalogConfigInput(
            server: _server(7, 'DE Catalog'),
            configBytes: utf8.encode(_catalogConfig(tag: 'proxy')),
          ),
        ],
      );
      expect(merged.nodes.any((n) => n.isCatalog), isTrue);

      final stripped = stripCatalogOutboundsFromConfig(merged.configJson);
      expect(stripped, isNotNull);
      expect(stripped!.contains('cat-7-'), isFalse);
      expect(stripped.contains('de-sub'), isTrue);
      expect(stripCatalogOutboundsFromConfig(stripped), isNull);
    });
  });

  group('selectionUsesCatalog', () {
    test('detects legacy and merged catalog picks', () {
      expect(selectionUsesCatalog(parseServerSelection('cat:3')), isTrue);
      expect(
        selectionUsesCatalog((
          isPersonal: true,
          catalogId: null,
          personalKind: TikNetPersonalPickKind.proxy,
          personalTag: 'cat-9-de',
          personalGroupTag: 'Select',
        )),
        isTrue,
      );
      expect(selectionUsesCatalog(smartSelection()), isFalse);
    });
  });
}
