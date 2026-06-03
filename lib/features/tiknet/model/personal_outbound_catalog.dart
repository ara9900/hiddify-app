import 'dart:convert';

import 'package:hiddify/utils/link_parsers.dart';

/// How the panel wants the server picker to behave.
enum TikNetServerDisplayMode {
  both,
  personalOnly,
  catalogOnly;

  static TikNetServerDisplayMode fromApi(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
        'personal_only' => TikNetServerDisplayMode.personalOnly,
        'catalog_only' => TikNetServerDisplayMode.catalogOnly,
        _ => TikNetServerDisplayMode.both,
      };
}

/// Special auto-pick modes from subscription (urltest / balancer).
enum TikNetPersonalPickKind {
  defaultAuto,
  urltest,
  balancer,
  proxy,
}

class TikNetPersonalAutoMode {
  const TikNetPersonalAutoMode({
    required this.kind,
    required this.tag,
    required this.groupTag,
    required this.title,
    required this.subtitle,
  });

  final TikNetPersonalPickKind kind;
  final String tag;
  final String groupTag;
  final String title;
  final String subtitle;
}

class TikNetPersonalProxyNode {
  const TikNetPersonalProxyNode({
    required this.tag,
    required this.groupTag,
    required this.label,
    this.probeUrl = '',
  });

  final String tag;
  final String groupTag;
  final String label;
  final String probeUrl;
}

class TikNetPersonalOutboundCatalog {
  const TikNetPersonalOutboundCatalog({
    required this.mainGroupTag,
    required this.autoModes,
    required this.nodes,
  });

  final String mainGroupTag;
  final List<TikNetPersonalAutoMode> autoModes;
  final List<TikNetPersonalProxyNode> nodes;

  bool get isEmpty => autoModes.isEmpty && nodes.isEmpty;
}

const _skipTypes = {'direct', 'block', 'dns', 'tun', 'interface'};

const _proxyUriSchemes = {
  'vless',
  'vmess',
  'trojan',
  'ss',
  'ssconf',
  'tuic',
  'hy2',
  'hysteria2',
  'hy',
  'hysteria',
  'ssh',
  'wg',
  'awg',
  'shadowtls',
  'mieru',
  'warp',
};

/// Pasargad / Hiddify subscription: base64 or plain lines of proxy URIs.
TikNetPersonalOutboundCatalog? parsePersonalOutboundsFromSubscriptionLinks(String rawContent) {
  var text = rawContent.trim();
  if (text.isEmpty) return null;

  if (!text.startsWith('{') && !text.startsWith('[')) {
    final decoded = safeDecodeBase64(text);
    if (decoded != text && decoded.contains('://')) {
      text = decoded;
    }
  }

  final lines = text.split(RegExp(r'\r?\n'));
  final nodes = <TikNetPersonalProxyNode>[];
  var index = 0;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;

    final uri = Uri.tryParse(line);
    if (uri == null || !_proxyUriSchemes.contains(uri.scheme.toLowerCase())) continue;

    final fragment = uri.hasFragment ? Uri.decodeComponent(uri.fragment.split(' -> ').first.trim()) : '';
    final label = fragment.isNotEmpty ? fragment : 'سرور ${index + 1}';
    final tag = fragment.isNotEmpty ? _safeTag(fragment, index) : 'node-$index';

    nodes.add(
      TikNetPersonalProxyNode(
        tag: tag,
        groupTag: 'proxy',
        label: label,
        probeUrl: _probeUrlFromProxyUri(uri),
      ),
    );
    index++;
  }

  if (nodes.isEmpty) return null;
  return TikNetPersonalOutboundCatalog(
    mainGroupTag: 'proxy',
    autoModes: const [],
    nodes: nodes,
  );
}

/// sing-box uses [type]; Xray / some Hiddify exports use [protocol].
String _outboundType(Map<String, dynamic> o) {
  return ((o['type'] ?? o['protocol']) as String?)?.toLowerCase() ?? '';
}

String _safeTag(String name, int index) {
  final t = name.replaceAll(RegExp(r'[^\w\-\.\u0600-\u06FF]+'), '_').trim();
  if (t.isNotEmpty && t.length <= 64) return t;
  return 'node-$index';
}

String _probeUrlFromProxyUri(Uri uri) {
  final host = uri.host;
  if (host.isEmpty) return '';
  final port = uri.hasPort ? uri.port : 443;
  if (port > 0 && port != 443) return 'https://$host:$port';
  return 'https://$host';
}

TikNetPersonalOutboundCatalog? parsePersonalOutboundsFromConfig(String rawConfig) {
  var trimmed = rawConfig.trim();
  if (trimmed.isEmpty) return null;

  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    final decoded = safeDecodeBase64(trimmed);
    if (decoded.startsWith('{') || decoded.startsWith('[')) {
      trimmed = decoded;
    }
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return null;
    var outboundsRaw = decoded['outbounds'] ?? decoded['endpoints'];
    if (outboundsRaw is! List) {
      final clashProxies = decoded['proxies'];
      if (clashProxies is List) {
        return _catalogFromClashProxies(decoded, clashProxies);
      }
      return null;
    }

    final outbounds = <Map<String, dynamic>>[];
    for (final o in outboundsRaw) {
      if (o is Map<String, dynamic>) outbounds.add(o);
    }
    if (outbounds.isEmpty) return null;

    final mainGroup = _resolveMainSelectorTag(decoded, outbounds);
    final autoModes = <TikNetPersonalAutoMode>[];
    final nodes = <TikNetPersonalProxyNode>[];

    final byTag = <String, Map<String, dynamic>>{};
    for (final o in outbounds) {
      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (tag.isNotEmpty) byTag[tag] = o;
    }

    for (final o in outbounds) {
      final type = _outboundType(o);
      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (tag.isEmpty) continue;

      if (type == 'urltest') {
        autoModes.add(
          TikNetPersonalAutoMode(
            kind: TikNetPersonalPickKind.urltest,
            tag: tag,
            groupTag: mainGroup,
            title: 'کمترین تأخیر',
            subtitle: 'خودکار؛ سریع‌ترین سرور بر اساس پینگ',
          ),
        );
        continue;
      }
      if (type == 'balancer') {
        autoModes.add(
          TikNetPersonalAutoMode(
            kind: TikNetPersonalPickKind.balancer,
            tag: tag,
            groupTag: mainGroup,
            title: 'تعادل بار',
            subtitle: 'توزیع اتصال بین سرورها برای پایداری',
          ),
        );
        continue;
      }
      if (_skipTypes.contains(type) || type == 'selector' || type == 'urltest' || type == 'balancer') {
        continue;
      }
      nodes.add(
        TikNetPersonalProxyNode(
          tag: tag,
          groupTag: mainGroup,
          label: _nodeLabel(o, tag),
          probeUrl: _probeUrlFromOutbound(o),
        ),
      );
    }

    if (nodes.isEmpty) {
      _appendNodesFromOutboundRefs(outbounds, mainGroup, nodes, byTag);
    }

    return TikNetPersonalOutboundCatalog(
      mainGroupTag: mainGroup,
      autoModes: autoModes,
      nodes: nodes,
    );
  } catch (_) {
    return null;
  }
}

void _appendNodesFromOutboundRefs(
  List<Map<String, dynamic>> outbounds,
  String mainGroup,
  List<TikNetPersonalProxyNode> nodes,
  Map<String, Map<String, dynamic>> byTag,
) {
  final seen = <String>{};
  const refTypes = {'selector', 'urltest', 'balancer'};

  for (final o in outbounds) {
    final type = _outboundType(o);
    if (!refTypes.contains(type)) continue;
    final refs = o['outbounds'];
    if (refs is! List) continue;
    final groupTag = (o['tag'] as String?)?.trim().isNotEmpty == true ? (o['tag'] as String).trim() : mainGroup;

    for (final ref in refs) {
      final tag = ref.toString().trim();
      if (tag.isEmpty || seen.contains(tag)) continue;
      if (tag == 'direct' || tag == 'block' || tag == 'dns' || tag == 'auto') continue;

      final def = byTag[tag];
      final defType = def != null ? _outboundType(def) : '';
      if (def != null && !_skipTypes.contains(defType) && defType != 'selector') {
        seen.add(tag);
        nodes.add(
          TikNetPersonalProxyNode(
            tag: tag,
            groupTag: groupTag,
            label: _nodeLabel(def, tag),
            probeUrl: _probeUrlFromOutbound(def),
          ),
        );
      } else if (def == null) {
        seen.add(tag);
        nodes.add(
          TikNetPersonalProxyNode(
            tag: tag,
            groupTag: groupTag,
            label: tag,
            probeUrl: '',
          ),
        );
      }
    }
  }
}

TikNetPersonalOutboundCatalog? _catalogFromClashProxies(
  Map<String, dynamic> config,
  List clashProxies,
) {
  final nodes = <TikNetPersonalProxyNode>[];
  for (var i = 0; i < clashProxies.length; i++) {
    final p = clashProxies[i];
    if (p is! Map) continue;
    final map = Map<String, dynamic>.from(p);
    final type = _outboundType(map);
    if (type.isEmpty || _skipTypes.contains(type)) continue;
    final name = (map['name'] as String?)?.trim();
    final tag = name?.isNotEmpty == true ? _safeTag(name!, i) : 'node-$i';
    nodes.add(
      TikNetPersonalProxyNode(
        tag: tag,
        groupTag: 'proxy',
        label: name?.isNotEmpty == true ? name! : tag,
        probeUrl: _probeUrlFromOutbound(map),
      ),
    );
  }
  if (nodes.isEmpty) return null;
  var mainGroup = 'proxy';
  final groups = config['proxy-groups'] ?? config['proxy_groups'];
  if (groups is List) {
    for (final g in groups) {
      if (g is! Map) continue;
      final gType = (g['type'] as String?)?.toLowerCase() ?? '';
      if (gType == 'url-test' || gType == 'urltest') {
        return TikNetPersonalOutboundCatalog(
          mainGroupTag: (g['name'] as String?)?.trim() ?? mainGroup,
          autoModes: [
            TikNetPersonalAutoMode(
              kind: TikNetPersonalPickKind.urltest,
              tag: (g['name'] as String?)?.trim() ?? 'auto',
              groupTag: mainGroup,
              title: 'کمترین تأخیر',
              subtitle: 'خودکار؛ سریع‌ترین سرور بر اساس پینگ',
            ),
          ],
          nodes: nodes,
        );
      }
    }
  }
  return TikNetPersonalOutboundCatalog(mainGroupTag: mainGroup, autoModes: const [], nodes: nodes);
}

String _resolveMainSelectorTag(Map<String, dynamic> config, List<Map<String, dynamic>> outbounds) {
  final route = config['route'];
  if (route is Map<String, dynamic>) {
    final fin = (route['final'] as String?)?.trim();
    if (fin != null && fin.isNotEmpty) return fin;
  }

  Map<String, dynamic>? best;
  var bestLen = -1;
  for (final o in outbounds) {
    if (_outboundType(o) != 'selector') continue;
    final outs = o['outbounds'];
    final len = outs is List ? outs.length : 0;
    if (len > bestLen) {
      bestLen = len;
      best = o;
    }
  }
  final tag = (best?['tag'] as String?)?.trim();
  if (tag != null && tag.isNotEmpty) return tag;
  return 'proxy';
}

String _nodeLabel(Map<String, dynamic> o, String tag) {
  final server = (o['server'] as String?)?.trim();
  if (server != null && server.isNotEmpty) return tag;
  return tag;
}

String _probeUrlFromOutbound(Map<String, dynamic> o) {
  final hosts = <String>[];
  void addHost(String? h) {
    final v = (h ?? '').trim();
    if (v.isNotEmpty && !hosts.contains(v)) hosts.add(v);
  }

  addHost(o['server'] as String?);
  addHost(o['address'] as String?);
  final tls = o['tls'];
  if (tls is Map) addHost(tls['server'] as String?);
  final reality = o['reality'];
  if (reality is Map) addHost(reality['server'] as String?);
  final transport = o['transport'];
  if (transport is Map) {
    final h = transport['host'];
    if (h is String) addHost(h);
    if (h is List && h.isNotEmpty) addHost(h.first.toString());
  }

  if (hosts.isEmpty) return '';
  final host = hosts.first;
  if (host.contains('://')) return host;
  final port = (o['server_port'] as num?)?.toInt();
  if (port != null && port > 0 && port != 443) return 'https://$host:$port';
  return 'https://$host';
}
