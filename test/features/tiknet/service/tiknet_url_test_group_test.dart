import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  test('urlTestGroupTagForCatalog prefers urltest outbound tag', () {
    const catalog = TikNetPersonalOutboundCatalog(
      mainGroupTag: 'select',
      autoModes: [
        TikNetPersonalAutoMode(
          kind: TikNetPersonalPickKind.urltest,
          tag: 'auto',
          groupTag: 'select',
          title: 'auto',
          subtitle: '',
        ),
      ],
      nodes: [
        TikNetPersonalProxyNode(tag: 'node-1', groupTag: 'select', label: 'N1'),
      ],
    );
    expect(urlTestGroupTagForCatalog(catalog), 'auto');
  });

  test('urlTestGroupTagForCatalog falls back to main selector', () {
    const catalog = TikNetPersonalOutboundCatalog(
      mainGroupTag: 'proxy',
      autoModes: [],
      nodes: [
        TikNetPersonalProxyNode(tag: 'a', groupTag: 'proxy', label: 'A'),
      ],
    );
    expect(urlTestGroupTagForCatalog(catalog), 'proxy');
  });

  test('resolveUrlTestGroupTag prefers group with catalog/Reality overlap', () {
    const catalog = TikNetPersonalOutboundCatalog(
      mainGroupTag: 'select',
      autoModes: [
        TikNetPersonalAutoMode(
          kind: TikNetPersonalPickKind.urltest,
          tag: 'auto',
          groupTag: 'select',
          title: 'auto',
          subtitle: '',
        ),
      ],
      nodes: [
        TikNetPersonalProxyNode(tag: 'cat-reality', groupTag: 'select', label: 'R'),
        TikNetPersonalProxyNode(tag: 'sub-a', groupTag: 'select', label: 'A'),
      ],
    );
    final groups = [
      OutboundGroup(
        tag: 'auto',
        items: [
          OutboundInfo(tag: 'sub-a', urlTestDelay: 0),
        ],
      ),
      OutboundGroup(
        tag: 'select',
        items: [
          OutboundInfo(tag: 'auto', urlTestDelay: 0),
          OutboundInfo(tag: 'cat-reality', urlTestDelay: 0),
          OutboundInfo(tag: 'sub-a', urlTestDelay: 0),
        ],
      ),
    ];
    expect(
      resolveUrlTestGroupTag(
        catalog: catalog,
        groups: groups,
        wanted: {'cat-reality', 'sub-a'},
      ),
      'select',
    );
  });
}
