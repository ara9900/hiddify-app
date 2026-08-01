import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:simple_icons/simple_icons.dart';

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
    'shadowsocks' => const Color(0xFF1A7DC0),
    'wireguard' => SimpleIconColors.wireguard,
    'hysteria' || 'hysteria2' => const Color(0xFFD81B60),
    'tuic' => const Color(0xFF3949AB),
    'warp' => SimpleIconColors.cloudflare,
    'ssh' => const Color(0xFF546E7A),
    'naive' => const Color(0xFF00897B),
    _ => TikNetColors.primary,
  };
}

/// Protocol brand mark used in the server picker / home card.
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
    final normalized = normalizeTikNetProtocol(protocol);
    final color = tikNetProtocolColor(normalized);
    final logoSize = size * 0.58;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.3),
      ),
      alignment: Alignment.center,
      child: _ProtocolLogo(protocol: normalized, size: logoSize, color: color),
    );
  }
}

class _ProtocolLogo extends StatelessWidget {
  const _ProtocolLogo({
    required this.protocol,
    required this.size,
    required this.color,
  });

  final String protocol;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (protocol) {
      'wireguard' => Icon(SimpleIcons.wireguard, size: size, color: SimpleIconColors.wireguard),
      'warp' => Icon(SimpleIcons.cloudflare, size: size, color: SimpleIconColors.cloudflare),
      'shadowsocks' => SvgPicture.string(_kShadowsocksSvg, width: size, height: size),
      'vless' => SvgPicture.string(_kVlessSvg, width: size, height: size),
      'vmess' => SvgPicture.string(_kVmessSvg, width: size, height: size),
      'trojan' => SvgPicture.string(_kTrojanSvg, width: size, height: size),
      'hysteria' || 'hysteria2' => SvgPicture.string(_kHysteriaSvg, width: size, height: size),
      'tuic' => SvgPicture.string(_kTuicSvg, width: size, height: size),
      'ssh' => SvgPicture.string(_kSshSvg, width: size, height: size),
      'naive' => SvgPicture.string(_kNaiveSvg, width: size, height: size),
      _ => Text(
          tikNetProtocolShortLabel(protocol),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.55,
            height: 1,
          ),
        ),
    };
  }
}

// Shadowsocks paper-plane mark (community logo geometry).
const _kShadowsocksSvg = '''
<svg viewBox="0 0 150 163" xmlns="http://www.w3.org/2000/svg">
  <path fill="#1A7DC0" d="M139.7 19l-24 100.8s-37-10.5-50.5-15l44-53.6-61 48.2L7.5 86zm-74.2 97.3l15.4 5L65 145z"/>
</svg>
''';

// VLESS — purple hexagon with V mark.
const _kVlessSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="#7C4DFF" d="M12 1.6 21.2 7v10L12 22.4 2.8 17V7L12 1.6z"/>
  <path fill="#FFFFFF" d="M8.1 7.8h2.15l1.75 5.35L13.75 7.8H15.9l-3.15 8.9h-1.7L8.1 7.8z"/>
</svg>
''';

// VMess — blue circle with V mark.
const _kVmessSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="10.2" fill="#1E88E5"/>
  <path fill="#FFFFFF" d="M7.9 7.5h2.2l1.9 5.8 1.9-5.8h2.2l-3.35 9.3h-1.7L7.9 7.5z"/>
</svg>
''';

// Trojan — amber shield.
const _kTrojanSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="#FB8C00" d="M12 2.2 19.5 5v6.4c0 4.7-3.1 9-7.5 10.4C7.6 20.4 4.5 16.1 4.5 11.4V5L12 2.2z"/>
  <path fill="#FFFFFF" d="M11.1 7.2h1.8v5.1l2.4 2.4-1.3 1.3-2.9-2.9V7.2z"/>
</svg>
''';

// Hysteria — magenta bolt mark.
const _kHysteriaSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <rect width="24" height="24" rx="6" fill="#D81B60"/>
  <path fill="#FFFFFF" d="M13.8 3.8 7.2 13.1h3.7l-.9 7.1 6.9-10.1h-3.8l.7-6.3z"/>
</svg>
''';

// TUIC — indigo diamond.
const _kTuicSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="#3949AB" d="M12 1.8 21.2 12 12 22.2 2.8 12 12 1.8z"/>
  <path fill="#FFFFFF" d="M8.4 9.1h7.2v1.7h-2.7v5.9h-1.8v-5.9H8.4V9.1z"/>
</svg>
''';

// SSH — slate terminal.
const _kSshSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <rect width="24" height="24" rx="6" fill="#546E7A"/>
  <path fill="#FFFFFF" d="M6.2 8.2 9.8 12l-3.6 3.8 1.5 1.4L12.8 12 7.7 6.8 6.2 8.2zm6.2 8.2h5.4v1.8h-5.4v-1.8z"/>
</svg>
''';

// NaiveProxy — teal N mark.
const _kNaiveSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <rect width="24" height="24" rx="6" fill="#00897B"/>
  <path fill="#FFFFFF" d="M7.2 6.8h2.3l5 7.2V6.8h2.3v10.4h-2.3l-5-7.2v7.2H7.2V6.8z"/>
</svg>
''';
