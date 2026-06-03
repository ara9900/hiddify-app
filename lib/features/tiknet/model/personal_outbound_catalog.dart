import 'dart:convert';

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

TikNetPersonalOutboundCatalog? parsePersonalOutboundsFromConfig(String rawConfig) {
  final trimmed = rawConfig.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return null;
    final outboundsRaw = decoded['outbounds'];
    if (outboundsRaw is! List) return null;

    final outbounds = <Map<String, dynamic>>[];
    for (final o in outboundsRaw) {
      if (o is Map<String, dynamic>) outbounds.add(o);
    }
    if (outbounds.isEmpty) return null;

    final mainGroup = _resolveMainSelectorTag(decoded, outbounds);
    final autoModes = <TikNetPersonalAutoMode>[];
    final nodes = <TikNetPersonalProxyNode>[];

    for (final o in outbounds) {
      final type = (o['type'] as String?)?.toLowerCase() ?? '';
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

    return TikNetPersonalOutboundCatalog(
      mainGroupTag: mainGroup,
      autoModes: autoModes,
      nodes: nodes,
    );
  } catch (_) {
    return null;
  }
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
    if ((o['type'] as String?)?.toLowerCase() != 'selector') continue;
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
