import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _prefsKeyV2 = 'tiknet_network_defaults_v2';

/// TikNet: use DNS from subscription profile (sing-box config), not a global DoH override.
///
/// v1 mistakenly set Cloudflare DoH and broke DNS for many users (connected UI, no traffic).
Future<void> applyTikNetNetworkDefaults(ProviderContainer container) async {
  if (!tikNetMode) return;

  final prefs = container.read(sharedPreferencesProvider).requireValue;
  if (prefs.getBool(_prefsKeyV2) == true) return;

  await _setRemoteDnsLocal(container);
  await prefs.setBool(_prefsKeyV2, true);
}

const _brokenRemoteDns = {
  'https://dns.cloudflare.com/dns-query',
  'https://1.1.1.1/dns-query',
  'tcp://8.8.8.8',
};

/// Fix DNS if a previous app version forced global DoH/TCP (breaks traffic in IR).
/// Returns true when DNS setting was changed (caller should reconnect VPN).
Future<bool> ensureTikNetDnsFromProfile(dynamic ref) async {
  if (!tikNetMode) return false;
  final current = ref.read(ConfigOptions.remoteDnsAddress);
  if (current == 'local') return false;
  if (_brokenRemoteDns.contains(current) || current.startsWith('https://')) {
    await ref.read(ConfigOptions.remoteDnsAddress.notifier).update('local');
    return true;
  }
  return false;
}

Future<void> _setRemoteDnsLocal(ProviderContainer container) async {
  await container.read(ConfigOptions.remoteDnsAddress.notifier).update('local');
}
