import 'dart:io';

import 'package:flutter/services.dart';

/// Snapshot from Android [get_network_diagnostics] platform channel.
class TikNetNativeNetworkSnapshot {
  const TikNetNativeNetworkSnapshot({
    required this.autoTime,
    required this.autoTimeZone,
    required this.airplaneMode,
    required this.privateDnsMode,
    required this.privateDnsSpecifier,
    required this.hasInternet,
    required this.validated,
    required this.isVpn,
    required this.isWifi,
    required this.isCellular,
    required this.isEthernet,
    required this.dnsServers,
    required this.alwaysOnVpnApp,
    required this.alwaysOnVpnLockdown,
    required this.ignoringBatteryOptimizations,
  });

  final bool autoTime;
  final bool autoTimeZone;
  final bool airplaneMode;
  final String privateDnsMode;
  final String? privateDnsSpecifier;
  final bool hasInternet;
  final bool validated;
  final bool isVpn;
  final bool isWifi;
  final bool isCellular;
  final bool isEthernet;
  final List<String> dnsServers;
  final String? alwaysOnVpnApp;
  final bool? alwaysOnVpnLockdown;
  final bool ignoringBatteryOptimizations;

  factory TikNetNativeNetworkSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return TikNetNativeNetworkSnapshot(
      autoTime: map['autoTime'] == true,
      autoTimeZone: map['autoTimeZone'] == true,
      airplaneMode: map['airplaneMode'] == true,
      privateDnsMode: (map['privateDnsMode'] as String?)?.trim().isNotEmpty == true
          ? (map['privateDnsMode'] as String).trim()
          : 'unknown',
      privateDnsSpecifier: (map['privateDnsSpecifier'] as String?)?.trim(),
      hasInternet: map['hasInternet'] == true,
      validated: map['validated'] == true,
      isVpn: map['isVpn'] == true,
      isWifi: map['isWifi'] == true,
      isCellular: map['isCellular'] == true,
      isEthernet: map['isEthernet'] == true,
      dnsServers: (map['dnsServers'] as List?)?.map((e) => '$e').toList() ?? const [],
      alwaysOnVpnApp: (map['alwaysOnVpnApp'] as String?)?.trim(),
      alwaysOnVpnLockdown: map['alwaysOnVpnLockdown'] is bool ? map['alwaysOnVpnLockdown'] as bool : null,
      ignoringBatteryOptimizations: map['ignoringBatteryOptimizations'] != false,
    );
  }
}

class TikNetPlatformDiagnostics {
  TikNetPlatformDiagnostics._();

  static const _channel = MethodChannel('com.hiddify.app/platform');

  static Future<TikNetNativeNetworkSnapshot?> getNetworkDiagnostics() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>('get_network_diagnostics');
      if (raw is Map) {
        return TikNetNativeNetworkSnapshot.fromMap(raw);
      }
    } catch (_) {}
    return null;
  }

  /// [target]: date | vpn | apn | private_dns | wireless | battery | airplane
  static Future<bool> openSystemSettings(String target) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('open_system_settings', {'target': target});
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
