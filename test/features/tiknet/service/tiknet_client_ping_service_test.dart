import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/service/tiknet_client_ping_service.dart';

void main() {
  test('measureCatalog preserves displayMode from input catalog', () async {
    const catalog = TikNetServerCatalog(
      personalAvailable: true,
      servers: [],
      displayMode: TikNetServerDisplayMode.personalOnly,
    );
    final service = TikNetClientPingService();
    final result = await service.measureCatalog(catalog);
    expect(result.displayMode, TikNetServerDisplayMode.personalOnly);
  });
}
