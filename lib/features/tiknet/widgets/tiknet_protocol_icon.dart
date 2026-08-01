import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';

/// User-facing label for panel catalog (app-exclusive emergency) servers.
const kTikNetAppExclusiveLabel = 'اختصاصی اپلیکیشن';

/// Normalize sing-box / share-link protocol ids for UI.
String normalizeTikNetProtocol(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  return switch (t) {
    'ss' || 'shadowsocksr' || 'xshadowsocks' => 'shadowsocks',
    'wg' || 'awg' => 'wireguard',
    'hy' => 'hysteria',
    'hy2' => 'hysteria2',
    'xvless' => 'vless',
    'xvmess' => 'vmess',
    'xtrojan' => 'trojan',
    _ => t,
  };
}

String tikNetProtocolShortLabel(String? protocol) {
  return switch (normalizeTikNetProtocol(protocol)) {
    'vless' => 'VL',
    'vmess' => 'VM',
    'trojan' => 'TJ',
    'shadowsocks' => 'SS',
    'wireguard' => 'WG',
    'hysteria' => 'Hy',
    'hysteria2' => 'H2',
    'tuic' => 'TU',
    'ssh' => 'SH',
    'warp' => 'WP',
    'naive' => 'NV',
    final other when other.isNotEmpty => other.length <= 2 ? other.toUpperCase() : other.substring(0, 2).toUpperCase(),
    _ => '?',
  };
}

Color tikNetProtocolColor(String? protocol) {
  return switch (normalizeTikNetProtocol(protocol)) {
    'vless' => const Color(0xFF7C4DFF),
    'vmess' => const Color(0xFF1E88E5),
    'trojan' => const Color(0xFFFB8C00),
    'shadowsocks' => const Color(0xFF43A047),
    'wireguard' => const Color(0xFF88171A),
    'hysteria' || 'hysteria2' => const Color(0xFFD81B60),
    'tuic' => const Color(0xFF3949AB),
    'warp' => const Color(0xFFF57C00),
    'ssh' => const Color(0xFF546E7A),
    _ => TikNetColors.primary,
  };
}

/// Protocol badge used in the server picker / home card (replaces generic key icon).
class TikNetProtocolIcon extends StatelessWidget {
  const TikNetProtocolIcon({
    super.key,
    this.protocol,
    this.size = 44,
  });

  final String? protocol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = tikNetProtocolColor(protocol);
    final label = tikNetProtocolShortLabel(protocol);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size * (label.length > 2 ? 0.28 : 0.34),
          letterSpacing: label.length > 2 ? -0.4 : 0.2,
          height: 1,
        ),
      ),
    );
  }
}
