import 'dart:convert';

import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';

/// Hosts a subscription entry can carry when it is not meant to be dialled.
const _unroutableHosts = {'0.0.0.0', '127.0.0.1', '::', '::1', 'localhost', '[::]', '[::1]'};

/// Share-link schemes we know how to inspect. Anything else is passed through.
const _knownSchemes = {
  'vless',
  'vmess',
  'trojan',
  'ss',
  'ssconf',
  'tuic',
  'hy',
  'hy2',
  'hysteria',
  'hysteria2',
  'ssh',
  'wg',
  'awg',
  'shadowtls',
  'mieru',
  'warp',
  'socks',
  'http',
  'https',
};

class TikNetSanitizedSubscription {
  const TikNetSanitizedSubscription({
    required this.payload,
    required this.droppedLabels,
    this.forcedXrayCount = 0,
  });

  final String payload;
  final List<String> droppedLabels;
  final int forcedXrayCount;

  bool get changed => droppedLabels.isNotEmpty || forcedXrayCount > 0;
}

/// Strips display-only "info" entries from a share-link subscription and forces
/// Reality links through ray2sing's Xray converter (`&core=xray`).
///
/// The panel keeps plan / traffic / expiry banners in the subscription so
/// v2rayNG and v2box can show them in their server lists. Our app reads those
/// numbers from the panel API, and the core would otherwise treat each banner
/// as a real proxy: it joins the balancer, wins urltest with a fake 0 ms and
/// then refuses every connection.
///
/// Reality links that work in v2rayNG need Xray's spiderX mapping. Stock
/// sing-box conversion drops `spx`; appending `core=xray` makes the patched
/// ray2sing take the Xray path even when the preference flag is not threaded
/// into the converter.
///
/// The payload shape is preserved (base64 stays base64) and the original text
/// is returned untouched whenever sanitising would leave no servers behind.
TikNetSanitizedSubscription sanitizeSubscriptionPayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.startsWith('{')) {
    return TikNetSanitizedSubscription(payload: raw, droppedLabels: const []);
  }

  final decoded = _tryDecodeBase64(text);
  final body = decoded ?? text;
  if (body.trim().startsWith('{') || !body.contains('://')) {
    return TikNetSanitizedSubscription(payload: raw, droppedLabels: const []);
  }

  final kept = <String>[];
  final dropped = <String>[];
  var serverCount = 0;
  var forcedXray = 0;

  for (final line in const LineSplitter().convert(body)) {
    final entry = line.trim();
    if (entry.isEmpty) continue;

    final label = _infoLabelOf(entry);
    if (label != null) {
      dropped.add(label);
      continue;
    }
    if (entry.contains('://')) serverCount++;
    final rewritten = _forceXrayCoreForReality(entry);
    if (rewritten != entry) forcedXray++;
    kept.add(rewritten);
  }

  if ((dropped.isEmpty && forcedXray == 0) || serverCount == 0) {
    return TikNetSanitizedSubscription(payload: raw, droppedLabels: const []);
  }

  final joined = kept.join('\n');
  return TikNetSanitizedSubscription(
    payload: decoded == null ? joined : base64Encode(utf8.encode(joined)),
    droppedLabels: dropped,
    forcedXrayCount: forcedXray,
  );
}

/// Appends `core=xray` to Reality VLESS/Trojan share links so ray2sing maps
/// spiderX the same way v2rayNG's Xray core does.
String _forceXrayCoreForReality(String entry) {
  final uri = Uri.tryParse(entry);
  if (uri == null || !uri.hasScheme) return entry;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'vless' && scheme != 'trojan') return entry;

  final params = Map<String, String>.from(uri.queryParameters);
  final security = (params['security'] ?? '').toLowerCase();
  if (security != 'reality') return entry;
  if ((params['core'] ?? '').toLowerCase() == 'xray') return entry;

  params['core'] = 'xray';
  return uri.replace(queryParameters: params).toString();
}

/// Returns the entry name when [entry] is a display-only banner, else null.
String? _infoLabelOf(String entry) {
  final uri = Uri.tryParse(entry);
  if (uri == null || !uri.hasScheme) return null;
  final scheme = uri.scheme.toLowerCase();
  if (!_knownSchemes.contains(scheme)) return null;

  if (scheme == 'vmess') return _vmessInfoLabel(entry);

  final name = _decodeFragment(uri.fragment);
  if (isPanelInfoLabel(name)) return name.isEmpty ? entry : name;

  final host = _hostOf(uri);
  if (host.isEmpty || _unroutableHosts.contains(host)) {
    return name.isEmpty ? entry : name;
  }
  final port = uri.hasPort ? uri.port : null;
  if (port != null && (port <= 0 || port > 65535)) {
    return name.isEmpty ? entry : name;
  }
  return null;
}

String? _vmessInfoLabel(String entry) {
  final payload = entry.substring(entry.indexOf('://') + 3).split('#').first;
  final decoded = _tryDecodeBase64(payload);
  if (decoded == null) return null;
  Map<String, dynamic> map;
  try {
    final parsed = jsonDecode(decoded);
    if (parsed is! Map) return null;
    map = Map<String, dynamic>.from(parsed);
  } catch (_) {
    return null;
  }

  final name = (map['ps'] as String?)?.trim() ?? '';
  final host = (map['add'] as String?)?.trim().toLowerCase() ?? '';
  final port = int.tryParse('${map['port'] ?? ''}');
  final isInfo = isPanelInfoLabel(name) ||
      host.isEmpty ||
      _unroutableHosts.contains(host) ||
      (port != null && (port <= 0 || port > 65535));
  if (!isInfo) return null;
  return name.isEmpty ? entry : name;
}

String _hostOf(Uri uri) {
  final host = uri.host.trim().toLowerCase();
  if (host.isNotEmpty) return host;
  // `ss://base64@host:port` and friends can leave Uri.host empty.
  final authority = uri.authority.trim();
  if (authority.isEmpty) return '';
  final afterUser = authority.contains('@') ? authority.split('@').last : authority;
  final colon = afterUser.lastIndexOf(':');
  return (colon <= 0 ? afterUser : afterUser.substring(0, colon)).toLowerCase();
}

String _decodeFragment(String fragment) {
  if (fragment.isEmpty) return '';
  try {
    return Uri.decodeComponent(fragment);
  } catch (_) {
    return fragment;
  }
}

String? _tryDecodeBase64(String value) {
  final compact = value.replaceAll(RegExp(r'\s'), '');
  if (compact.isEmpty || compact.contains('://')) return null;
  if (!RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) return null;
  final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
  try {
    return utf8.decode(base64Decode(padded));
  } catch (_) {
    return null;
  }
}
