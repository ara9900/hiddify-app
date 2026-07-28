import 'dart:convert';

import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/utils/link_parsers.dart';

const _groupTypes = {'selector', 'urltest', 'balancer'};
const _skipOutboundTypes = {
  'direct',
  'block',
  'dns',
  'tun',
  'interface',
  'freedom',
  'blackhole',
  'selector',
  'urltest',
  'balancer',
};

class TikNetCatalogConfigInput {
  const TikNetCatalogConfigInput({
    required this.server,
    required this.configBytes,
  });

  final TikNetServerEntry server;
  final List<int> configBytes;
}

class TikNetMergedConfigResult {
  const TikNetMergedConfigResult({
    required this.configJson,
    required this.mainGroupTag,
    required this.nodes,
  });

  final String configJson;
  final String mainGroupTag;
  final List<TikNetPersonalProxyNode> nodes;

  bool get isEmpty => nodes.isEmpty;
}

/// Merges subscription sing-box JSON with catalog server configs into one profile.
TikNetMergedConfigResult mergeTikNetConfigs({
  String? subscriptionRaw,
  List<TikNetCatalogConfigInput> catalogConfigs = const [],
}) {
  final base = _parseSingboxMap(subscriptionRaw);
  final outbounds = <Map<String, dynamic>>[];
  final usedTags = <String>{};
  final nodes = <TikNetPersonalProxyNode>[];

  String mainGroup = 'Select';

  if (base != null) {
    final baseOuts = _outboundsList(base);
    for (final o in baseOuts) {
      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (tag.isNotEmpty) usedTags.add(tag);
      outbounds.add(Map<String, dynamic>.from(o));
    }
    mainGroup = _resolveSelectorTag(baseOuts) ?? mainGroup;

    for (final o in baseOuts) {
      final type = _typeOf(o);
      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (tag.isEmpty || _skipOutboundTypes.contains(type)) continue;
      nodes.add(
        TikNetPersonalProxyNode(
          tag: tag,
          groupTag: mainGroup,
          label: _labelOf(o, tag),
        ),
      );
    }
  }

  for (final input in catalogConfigs) {
    if (!input.server.accessible || input.server.id <= 0) continue;
    final extracted = _extractCatalogOutbounds(
      input.configBytes,
      catalogId: input.server.id,
      displayName: input.server.name,
      usedTags: usedTags,
    );
    if (extracted.isEmpty) continue;

    for (final item in extracted) {
      outbounds.add(item.outbound);
      usedTags.add(item.tag);
      if (item.isSelectable) {
        nodes.add(
          TikNetPersonalProxyNode(
            tag: item.tag,
            groupTag: mainGroup,
            label: item.label,
            source: TikNetNodeSource.catalog,
            catalogId: input.server.id,
          ),
        );
      }
    }
  }

  if (nodes.isEmpty) {
    return const TikNetMergedConfigResult(configJson: '', mainGroupTag: 'Select', nodes: []);
  }

  // Ensure selector exists and lists all selectable nodes.
  final selectableTags = nodes.map((n) => n.tag).toList();
  var selectorIndex = outbounds.indexWhere((o) => _typeOf(o) == 'selector' && (o['tag'] as String?)?.trim() == mainGroup);
  if (selectorIndex < 0) {
    selectorIndex = outbounds.indexWhere((o) => _typeOf(o) == 'selector');
    if (selectorIndex >= 0) {
      mainGroup = (outbounds[selectorIndex]['tag'] as String?)?.trim() ?? mainGroup;
    }
  }

  if (selectorIndex >= 0) {
    final sel = Map<String, dynamic>.from(outbounds[selectorIndex]);
    sel['outbounds'] = _mergeOutboundTagList(sel['outbounds'], selectableTags);
    if (sel['default'] == null || sel['default'].toString().trim().isEmpty) {
      sel['default'] = selectableTags.first;
    }
    outbounds[selectorIndex] = sel;
    // Keep node.groupTag aligned.
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      nodes[i] = TikNetPersonalProxyNode(
        tag: n.tag,
        groupTag: mainGroup,
        label: n.label,
        probeUrl: n.probeUrl,
        source: n.source,
        catalogId: n.catalogId,
      );
    }
  } else {
    outbounds.insert(
      0,
      {
        'type': 'selector',
        'tag': mainGroup,
        'outbounds': selectableTags,
        'default': selectableTags.first,
      },
    );
  }

  // Critical for Reality/catalog ping: urltest groups (e.g. "auto") must list the
  // same leaf tags. Merge previously only updated the selector, so urltest stayed
  // subscription-only and Reality catalog nodes never received delays.
  for (var i = 0; i < outbounds.length; i++) {
    if (_typeOf(outbounds[i]) != 'urltest') continue;
    final ut = Map<String, dynamic>.from(outbounds[i]);
    ut['outbounds'] = _mergeOutboundTagList(ut['outbounds'], selectableTags);
    outbounds[i] = ut;
  }

  // Ensure at least one urltest group exists for ping/smart-connect.
  final hasUrltest = outbounds.any((o) => _typeOf(o) == 'urltest');
  if (!hasUrltest) {
    final selIdx = outbounds.indexWhere((o) => _typeOf(o) == 'selector');
    final insertAt = selIdx < 0 ? 0 : (selIdx + 1).clamp(0, outbounds.length);
    outbounds.insert(
      insertAt,
      {
        'type': 'urltest',
        'tag': 'auto',
        'outbounds': List<String>.from(selectableTags),
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '10m',
        'tolerance': 50,
      },
    );
    // Prefer auto inside selector when we just created it.
    if (selIdx >= 0) {
      final sel = Map<String, dynamic>.from(outbounds[selIdx]);
      sel['outbounds'] = _mergeOutboundTagList(['auto'], _tagList(sel['outbounds']));
      outbounds[selIdx] = sel;
    }
  }

  if (!usedTags.contains('direct')) {
    outbounds.add({'type': 'direct', 'tag': 'direct'});
  }
  if (!usedTags.contains('block')) {
    outbounds.add({'type': 'block', 'tag': 'block'});
  }

  final config = <String, dynamic>{
    if (base != null) ...base,
    'outbounds': outbounds,
  };
  final route = config['route'];
  if (route is Map<String, dynamic>) {
    route['final'] = mainGroup;
  } else {
    config['route'] = {'final': mainGroup};
  }

  return TikNetMergedConfigResult(
    configJson: const JsonEncoder.withIndent('  ').convert(config),
    mainGroupTag: mainGroup,
    nodes: nodes,
  );
}

class _ExtractedOutbound {
  const _ExtractedOutbound({
    required this.tag,
    required this.label,
    required this.outbound,
    required this.isSelectable,
  });

  final String tag;
  final String label;
  final Map<String, dynamic> outbound;
  final bool isSelectable;
}

List<_ExtractedOutbound> _extractCatalogOutbounds(
  List<int> bytes, {
  required int catalogId,
  required String displayName,
  required Set<String> usedTags,
}) {
  final raw = utf8.decode(bytes, allowMalformed: true).trim();
  if (raw.isEmpty) return const [];

  var text = raw;
  if (!text.startsWith('{') && !text.startsWith('[')) {
    final decoded = safeDecodeBase64(text);
    if (decoded.startsWith('{') || decoded.startsWith('[')) text = decoded;
  }

  Map<String, dynamic>? map;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      map = decoded;
    } else if (decoded is Map) {
      map = Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const [];
  }
  if (map == null) return const [];

  final outs = _outboundsList(map);
  if (outs.isEmpty) return const [];

  final rename = <String, String>{};
  for (final o in outs) {
    final old = (o['tag'] as String?)?.trim() ?? '';
    if (old.isEmpty) continue;
    var neu = 'cat-$catalogId-${_sanitizeTag(old)}';
    var i = 2;
    while (usedTags.contains(neu) || rename.values.contains(neu)) {
      neu = 'cat-$catalogId-${_sanitizeTag(old)}-$i';
      i++;
    }
    rename[old] = neu;
  }
  if (rename.isEmpty) return const [];

  final result = <_ExtractedOutbound>[];
  var selectableCount = 0;
  for (final o in outs) {
    final type = _typeOf(o);
    final oldTag = (o['tag'] as String?)?.trim() ?? '';
    if (oldTag.isEmpty || _groupTypes.contains(type) || type == 'direct' || type == 'block' || type == 'dns' || type == 'tun') {
      continue;
    }
    final neu = rename[oldTag]!;
    final copy = _deepCopyMap(o);
    _rewriteTagsInOutbound(copy, rename);
    copy['tag'] = neu;

    final selectable = !_skipOutboundTypes.contains(type);
    final label = selectable
        ? (displayName.trim().isNotEmpty
            ? (selectableCount == 0 ? displayName.trim() : '${displayName.trim()} · ${_labelOf(o, oldTag)}')
            : neu)
        : neu;
    if (selectable) selectableCount++;

    result.add(
      _ExtractedOutbound(
        tag: neu,
        label: label,
        outbound: copy,
        isSelectable: selectable,
      ),
    );
  }
  return result;
}

Map<String, dynamic>? _parseSingboxMap(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.startsWith('{')) {
    final decoded = safeDecodeBase64(text);
    if (decoded.startsWith('{')) text = decoded;
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

List<Map<String, dynamic>> _outboundsList(Map<String, dynamic> config) {
  final raw = config['outbounds'] ?? config['endpoints'];
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map<String, dynamic>) {
      out.add(Map<String, dynamic>.from(e));
    } else if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

String? _resolveSelectorTag(List<Map<String, dynamic>> outbounds) {
  Map<String, dynamic>? best;
  var bestLen = -1;
  for (final o in outbounds) {
    if (_typeOf(o) != 'selector') continue;
    final outs = o['outbounds'];
    final len = outs is List ? outs.length : 0;
    if (len > bestLen) {
      bestLen = len;
      best = o;
    }
  }
  final tag = (best?['tag'] as String?)?.trim();
  return (tag != null && tag.isNotEmpty) ? tag : null;
}

String _typeOf(Map<String, dynamic> o) {
  final type = ((o['type'] as String?) ?? '').trim().toLowerCase();
  if (type.isNotEmpty) return type;
  // Some catalog/Xray-shaped payloads use "protocol" instead of "type".
  return ((o['protocol'] as String?) ?? '').trim().toLowerCase();
}

List<String> _tagList(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final e in raw) {
    final t = e.toString().trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

List<String> _mergeOutboundTagList(dynamic existingRaw, List<String> extra) {
  final merged = <String>[];
  final seen = <String>{};
  for (final t in [..._tagList(existingRaw), ...extra]) {
    if (seen.add(t)) merged.add(t);
  }
  return merged;
}

String _labelOf(Map<String, dynamic> o, String tag) {
  final server = (o['server'] as String?)?.trim();
  if (server != null && server.isNotEmpty) return tag;
  return tag;
}

String _sanitizeTag(String tag) {
  final cleaned = tag.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]+'), '_');
  if (cleaned.isEmpty) return 'node';
  return cleaned.length > 48 ? cleaned.substring(0, 48) : cleaned;
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> src) {
  return jsonDecode(jsonEncode(src)) as Map<String, dynamic>;
}

void _rewriteTagsInOutbound(Map<String, dynamic> outbound, Map<String, String> rename) {
  void rewriteList(dynamic value) {
    if (value is! List) return;
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is String) {
        final neu = rename[item];
        if (neu != null) value[i] = neu;
      }
    }
  }

  rewriteList(outbound['outbounds']);
  for (final key in ['detour', 'dialer_proxy', 'outbound']) {
    final v = outbound[key];
    if (v is String && rename.containsKey(v)) {
      outbound[key] = rename[v];
    }
  }
}
