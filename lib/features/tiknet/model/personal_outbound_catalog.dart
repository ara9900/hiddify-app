import 'dart:convert';

import 'package:hiddify/features/tiknet/model/tiknet_core_tags.dart';
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

/// How the user picks a config from the subscription / smart mode.
enum TikNetPersonalPickKind {
  /// Legacy default (maps to smart in UI).
  defaultAuto,
  /// Ping all subscription configs, connect to lowest latency; stick until reconnect.
  smart,
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
    this.source = TikNetNodeSource.subscription,
    this.catalogId,
    this.protocol = '',
  });

  final String tag;
  final String groupTag;
  final String label;
  final String probeUrl;
  final TikNetNodeSource source;
  final int? catalogId;

  /// sing-box / share-link type (`vless`, `wireguard`, `shadowsocks`, …).
  final String protocol;

  bool get isCatalog => source == TikNetNodeSource.catalog;

  /// Name shown in the picker / home card. Strips the core's uniqueness suffix.
  String get displayLabel => stripHiddifyTagSuffix(label.isNotEmpty ? label : tag);
}

/// Hiddify's share-link → sing-box converter appends `§ N` so outbound tags stay
/// unique (e.g. `Germany-1 § 3`). That marker is internal; the stock UI already
/// strips it, and TikNet must do the same for every user-facing label.
String stripHiddifyTagSuffix(String tag) {
  final cut = tag.indexOf('§');
  if (cut < 0) return tag.trimRight();
  return tag.substring(0, cut).trimRight();
}

enum TikNetNodeSource {
  subscription,
  catalog,
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

const _skipTypes = {'direct', 'block', 'dns', 'tun', 'interface', 'freedom', 'blackhole'};
const _xraySkipProtocols = {'freedom', 'blackhole', 'dns', 'socks', 'http', 'api'};

/// Hosts that can never be dialled from the phone.
const _unroutableHosts = {'0.0.0.0', '127.0.0.1', '::', '::1', 'localhost', '[::]', '[::1]'};

/// Phrases that only ever appear in subscription "info" entries: the plan,
/// traffic and expiry banners a panel ships so v2rayNG / v2box can display them
/// in their server list. They are not proxies and must never reach the profile.
const _infoTagPhrases = {
  'باقی مانده',
  'باقی‌مانده',
  'باقیمانده',
  'منقضی',
  'حجم مصرف',
  'تاریخ انقضا',
  'روز مانده',
  'traffic:',
  'traffic remaining',
  'remaining traffic',
  'expire:',
  'expires:',
  'expiry',
  'days left',
  'used:',
};

/// True for a subscription entry that exists only to show text to the user.
///
/// Panels publish these as real outbounds (usually at `0.0.0.0:1234`) so other
/// clients render them as rows in their server list. Our own UI reads plan and
/// traffic figures from the panel API instead, so we drop them — otherwise the
/// core dials them and every request routed there fails.
///
/// A panel can mark an entry explicitly with `"tiknet_info": true`, which is
/// the only fully reliable signal; the phrase list below is the fallback for
/// panels we do not control (Pasargard / Sanaei style banners).
bool isPanelInfoOutbound(Map<String, dynamic> o) {
  if (o['tiknet_info'] == true) return true;
  return isPanelInfoLabel((o['tag'] as String?) ?? '');
}

/// True when a node name reads as an informational banner rather than a server.
bool isPanelInfoLabel(String label) {
  final text = label.toLowerCase();
  if (text.isEmpty) return false;
  return _infoTagPhrases.any(text.contains);
}

/// True when an outbound can never carry traffic, or is a display-only banner.
bool isUnroutableOutbound(Map<String, dynamic> o) {
  final type = _outboundType(o);
  if (type.isEmpty || _skipTypes.contains(type) || _groupOutboundTypes.contains(type)) return false;

  if (isPanelInfoOutbound(o)) return true;

  final port = (o['server_port'] as num?)?.toInt() ?? (o['port'] as num?)?.toInt();
  if (port != null && (port <= 0 || port > 65535)) return true;

  // Covers sing-box `server` as well as Xray `settings.vnext[].address`.
  final target = parseProbeTarget(_probeUrlFromOutbound(o));
  if (target == null) {
    // No dialable host anywhere; only peer / detour based outbounds still work.
    return o['peers'] is! List && o['detour'] is! String;
  }
  return _unroutableHosts.contains(target.host.toLowerCase());
}

const _groupOutboundTypes = {'selector', 'urltest', 'balancer'};

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
  'wireguard',
  'awg',
  'shadowtls',
  'mieru',
  'warp',
};

/// Hiddify `/xray/` body: JSON array of per-server Xray configs — valid for listing only, not for sing-box core.
bool isHiddifyXraySubscriptionBundle(String rawContent) {
  var trimmed = rawContent.trim();
  if (trimmed.isEmpty) return false;
  if (!trimmed.startsWith('[')) {
    final decoded = safeDecodeBase64(trimmed);
    if (!decoded.startsWith('[')) return false;
    trimmed = decoded;
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! List || decoded.isEmpty) return false;
    final first = decoded.first;
    if (first is! Map) return false;
    final map = Map<String, dynamic>.from(first);
    return map.containsKey('remarks') && map['outbounds'] is List;
  } catch (_) {
    return false;
  }
}

/// Parses panel/subscription bytes into a catalog (for deciding phone-side fetch).
TikNetPersonalOutboundCatalog? parsePersonalOutboundsFromAny(String rawContent) {
  final trimmed = rawContent.trim();
  if (trimmed.isEmpty) return null;
  var catalog = parsePersonalOutboundsFromConfig(trimmed);
  if (catalog == null || catalog.nodes.isEmpty) {
    final links = parsePersonalOutboundsFromSubscriptionLinks(trimmed);
    if (links != null && links.nodes.isNotEmpty) return links;
  }
  return catalog;
}

/// True when we should import via [ProfileRepository.upsertRemote] on the phone.
bool shouldFetchSubscriptionOnDevice(String panelContent, String subscriptionUrl) {
  final url = subscriptionUrl.trim();
  if (!url.toLowerCase().startsWith('http')) return false;
  if (isHiddifyXraySubscriptionBundle(panelContent)) return true;
  final catalog = parsePersonalOutboundsFromAny(panelContent);
  return catalog == null || catalog.nodes.isEmpty;
}

/// Hiddify user page URLs need /singbox/ for VPN core (not /xray/ JSON bundle).
String normalizeSubscriptionFetchUrl(String rawUrl) {
  var url = rawUrl.trim();
  final hash = url.indexOf('#');
  if (hash >= 0) url = url.substring(0, hash).trim();
  if (url.isEmpty || !url.toLowerCase().startsWith('http')) return url;
  final lower = url.toLowerCase();
  if (lower.contains('/xray/') || lower.endsWith('/xray')) {
    url = url.replaceAll(RegExp(r'/xray/?$', caseSensitive: false), '/singbox/');
    if (!url.endsWith('/')) url = '$url/';
    return url;
  }
  if (lower.contains('/singbox') || lower.contains('/sub/')) {
    return url.endsWith('/') ? url : '$url/';
  }
  final uuid = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    caseSensitive: false,
  ).firstMatch(url);
  if (uuid != null) {
    final tail = url.substring(uuid.end).toLowerCase();
    if (tail.isEmpty || tail == '/') {
      if (!url.endsWith('/')) url = '$url/';
      return '${url}singbox/';
    }
  }
  return url;
}

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
    final label = fragment.isNotEmpty ? stripHiddifyTagSuffix(fragment) : 'سرور ${index + 1}';
    final tag = fragment.isNotEmpty ? _safeTag(fragment, index) : 'node-$index';

    nodes.add(
      TikNetPersonalProxyNode(
        tag: tag,
        groupTag: kCoreSelectorTag,
        label: label,
        probeUrl: _probeUrlFromProxyUri(uri),
        protocol: uri.scheme.toLowerCase(),
      ),
    );
    index++;
  }

  if (nodes.isEmpty) return null;
  return TikNetPersonalOutboundCatalog(
    mainGroupTag: kCoreSelectorTag,
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
    if (decoded is List) {
      return _catalogFromXrayConfigBundle(decoded);
    }
    if (decoded is! Map<String, dynamic>) return null;
    // sing-box 1.11+ puts WireGuard (and similar) under `endpoints`, while
    // classic proxies stay in `outbounds`. Both must be listed in the picker.
    final outbounds = _mapsFromConfigSections(decoded, const ['outbounds', 'endpoints']);
    if (outbounds.isEmpty) {
      final clashProxies = decoded['proxies'];
      if (clashProxies is List) {
        return _catalogFromClashProxies(decoded, clashProxies);
      }
      return null;
    }

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
      if (isUnroutableOutbound(o)) continue;
      nodes.add(
        TikNetPersonalProxyNode(
          tag: tag,
          groupTag: mainGroup,
          label: _nodeLabel(o, tag),
          probeUrl: _probeUrlFromOutbound(o),
          protocol: type,
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
            protocol: defType,
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
        groupTag: kCoreSelectorTag,
        label: name?.isNotEmpty == true ? name! : tag,
        probeUrl: _probeUrlFromOutbound(map),
        protocol: type,
      ),
    );
  }
  if (nodes.isEmpty) return null;
  var mainGroup = kCoreSelectorTag;
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
  return kCoreSelectorTag;
}

String _nodeLabel(Map<String, dynamic> o, String tag) {
  // Prefer remarks / name when present; always strip the core's `§ N` suffix.
  final remarks = (o['remarks'] as String?)?.trim();
  if (remarks != null && remarks.isNotEmpty) return stripHiddifyTagSuffix(remarks);
  final name = (o['name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return stripHiddifyTagSuffix(name);
  return stripHiddifyTagSuffix(tag);
}

/// Hiddify `/xray/` subscription: JSON array — one object per server (see remarks + outbounds).
TikNetPersonalOutboundCatalog? _catalogFromXrayConfigBundle(List<dynamic> items) {
  final nodes = <TikNetPersonalProxyNode>[];
  final seenTags = <String>{};

  for (var i = 0; i < items.length; i++) {
    if (items[i] is! Map) continue;
    final config = Map<String, dynamic>.from(items[i] as Map);
    final remarks = (config['remarks'] as String?)?.trim() ?? '';
    final outbounds = config['outbounds'];
    if (outbounds is! List) continue;

    for (final raw in outbounds) {
      if (raw is! Map) continue;
      final o = Map<String, dynamic>.from(raw);
      final protocol = _outboundType(o);
      if (protocol.isEmpty || _xraySkipProtocols.contains(protocol)) continue;
      if (_skipTypes.contains(protocol)) continue;

      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (tag.isEmpty || seenTags.contains(tag)) continue;
      if (tag == 'direct' || tag == 'block' || tag == 'fragment' || tag == 'proxy' || tag == 'api') {
        continue;
      }

      seenTags.add(tag);
      final label = stripHiddifyTagSuffix(remarks.isNotEmpty ? remarks : tag);
      nodes.add(
        TikNetPersonalProxyNode(
          tag: tag,
          groupTag: kCoreSelectorTag,
          label: label,
          probeUrl: _probeUrlFromOutbound(o),
          protocol: protocol,
        ),
      );
      break;
    }
  }

  if (nodes.isEmpty) return null;
  return TikNetPersonalOutboundCatalog(
    mainGroupTag: kCoreSelectorTag,
    autoModes: const [],
    nodes: nodes,
  );
}

/// Host+port for TCP reachability probes (from [TikNetPersonalProxyNode.probeUrl]).
({String host, int port})? parseProbeTarget(String probeUrl) {
  final raw = probeUrl.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (uri == null) return null;
  final host = uri.host.trim();
  if (host.isEmpty) return null;
  final port = uri.hasPort ? uri.port : 443;
  if (port <= 0 || port > 65535) return null;
  return (host: host, port: port);
}

String _probeUrlFromOutbound(Map<String, dynamic> o) {
  final type = _outboundType(o);
  final hosts = <String>[];
  void addHost(String? h) {
    var v = (h ?? '').trim();
    if (v.isEmpty) return;
    // WireGuard local address often looks like "10.0.0.9/32".
    final slash = v.indexOf('/');
    if (slash > 0) v = v.substring(0, slash);
    if (v.isNotEmpty && !hosts.contains(v)) hosts.add(v);
  }

  int? nestedPort;
  // Peers first — WireGuard endpoints dial peers[], not the tunnel address.
  final peers = o['peers'];
  if (peers is List) {
    for (final p in peers) {
      if (p is! Map) continue;
      addHost(p['address'] as String?);
      addHost(p['server'] as String?);
      nestedPort ??= (p['port'] as num?)?.toInt() ?? (p['server_port'] as num?)?.toInt();
    }
  }

  addHost(o['server'] as String?);
  // WG/WARP `address` is the tunnel interface CIDR, not a remote probe host.
  if (type != 'wireguard' && type != 'warp') {
    addHost(o['address'] as String?);
  }
  final settings = o['settings'];
  if (settings is Map<String, dynamic>) {
    final vnext = settings['vnext'];
    if (vnext is List) {
      for (final vn in vnext) {
        if (vn is Map) {
          addHost(vn['address'] as String?);
          nestedPort ??= (vn['port'] as num?)?.toInt();
        }
      }
    }
    final servers = settings['servers'];
    if (servers is List) {
      for (final s in servers) {
        if (s is Map) {
          addHost(s['address'] as String?);
          nestedPort ??= (s['port'] as num?)?.toInt();
        }
      }
    }
  }
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
  final port = (o['server_port'] as num?)?.toInt() ?? (o['port'] as num?)?.toInt() ?? nestedPort;
  if (port != null && port > 0 && port != 443) return 'https://$host:$port';
  return 'https://$host';
}

/// Collect outbound/endpoint objects from one or more top-level config keys.
List<Map<String, dynamic>> _mapsFromConfigSections(
  Map<String, dynamic> config,
  List<String> keys,
) {
  final out = <Map<String, dynamic>>[];
  final seenTags = <String>{};
  for (final key in keys) {
    final raw = config[key];
    if (raw is! List) continue;
    for (final e in raw) {
      Map<String, dynamic>? map;
      if (e is Map<String, dynamic>) {
        map = e;
      } else if (e is Map) {
        map = Map<String, dynamic>.from(e);
      }
      if (map == null) continue;
      final tag = (map['tag'] as String?)?.trim() ?? '';
      if (tag.isNotEmpty && !seenTags.add(tag)) continue;
      out.add(map);
    }
  }
  return out;
}
