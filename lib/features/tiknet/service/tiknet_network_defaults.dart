import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _prefsKey = 'tiknet_network_defaults_v1';

/// One-time DNS tuning for TikNet (plain TCP 8.8.8.8 often fails before tunnel is up).
Future<void> applyTikNetNetworkDefaults(ProviderContainer container) async {
  if (!tikNetMode) return;

  final prefs = container.read(sharedPreferencesProvider).requireValue;
  if (prefs.getBool(_prefsKey) == true) return;

  await container.read(ConfigOptions.remoteDnsAddress.notifier).update('https://dns.cloudflare.com/dns-query');
  await prefs.setBool(_prefsKey, true);
}
