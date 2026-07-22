import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('catalogWithoutClientPing preserves displayMode from input catalog', () {
    const catalog = TikNetServerCatalog(
      personalAvailable: true,
      servers: [],
      displayMode: TikNetServerDisplayMode.personalOnly,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(tikNetClientPingServiceProvider);
    final result = service.catalogWithoutClientPing(catalog);
    expect(result.displayMode, TikNetServerDisplayMode.personalOnly);
  });
}
