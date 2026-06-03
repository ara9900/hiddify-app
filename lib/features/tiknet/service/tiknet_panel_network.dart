import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _allowedRemoteDns = {
  'local',
  'tcp://8.8.8.8',
  'tcp://1.1.1.1',
  'tcp://4.4.2.2',
  'https://1.1.1.1/dns-query',
  'https://dns.cloudflare.com/dns-query',
};

const _allowedDirectDns = {
  'local',
  'udp://1.1.1.1',
  'udp://1.1.1.2',
  'udp://223.5.5.5',
  'tcp://1.1.1.1',
  'https://1.1.1.1/dns-query',
  'https://dns.cloudflare.com/dns-query',
  '4.4.2.2',
  '8.8.8.8',
};

/// Apply [network] from GET /api/customer/app-config. Returns true if settings changed.
Future<bool> applyPanelNetworkSettings(dynamic ref, Map<String, dynamic>? network) async {
  if (!tikNetMode || network == null) return false;

  final remoteRaw = (network['remote_dns'] as String?)?.trim();
  final directRaw = (network['direct_dns'] as String?)?.trim();

  var changed = false;

  if (remoteRaw != null && remoteRaw.isNotEmpty && _allowedRemoteDns.contains(remoteRaw)) {
    final current = ref.read(ConfigOptions.remoteDnsAddress);
    if (current != remoteRaw) {
      await ref.read(ConfigOptions.remoteDnsAddress.notifier).update(remoteRaw);
      changed = true;
    }
  }

  if (directRaw != null && directRaw.isNotEmpty && _allowedDirectDns.contains(directRaw)) {
    final current = ref.read(ConfigOptions.directDnsAddress);
    if (current != directRaw) {
      await ref.read(ConfigOptions.directDnsAddress.notifier).update(directRaw);
      changed = true;
    }
  }

  if (changed && ref.read(connectionNotifierProvider).valueOrNull is Connected) {
    await ref.read(connectionNotifierProvider.notifier).reconnect(
      ref.read(activeProfileProvider).valueOrNull,
    );
  }

  return changed;
}
