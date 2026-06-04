import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';

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
}
