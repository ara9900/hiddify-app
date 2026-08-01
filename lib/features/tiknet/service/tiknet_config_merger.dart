import 'dart:convert';

import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';
import 'package:hiddify/features/tiknet/model/server_catalog.dart';
import 'package:hiddify/features/tiknet/model/tiknet_core_tags.dart';
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
  final endpoints = <Map<String, dynamic>>[];
  final usedTags = <String>{};
  final nodes = <TikNetPersonalProxyNode>[];

  String mainGroup = kCoreSelectorTag;
  final droppedTags = <String>{};

  if (base != null) {
    final baseOuts = <Map<String, dynamic>>[];
    for (final o in _sectionMaps(base, 'outbounds')) {
      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (isUnroutableOutbound(o)) {
        // Panel banner entries ("ترافیک باقی مانده" and friends) are shipped as
        // real outbounds pointing at 0.0.0.0. The core happily dials them and
        // every request routed there fails, so they must not reach the profile.
        if (tag.isNotEmpty) droppedTags.add(tag);
        continue;
      }
      baseOuts.add(o);
      if (tag.isNotEmpty) usedTags.add(tag);
      outbounds.add(Map<String, dynamic>.from(o));
    }
    for (final o in _sectionMaps(base, 'endpoints')) {
      final tag = (o['tag'] as String?)?.trim() ?? '';
      if (isUnroutableOutbound(o)) {
        if (tag.isNotEmpty) droppedTags.add(tag);
        continue;
      }
      if (tag.isNotEmpty) usedTags.add(tag);
      endpoints.add(Map<String, dynamic>.from(o));
    }
    mainGroup = _resolveSelectorTag(baseOuts) ?? mainGroup;

    for (final o in [...baseOuts, ...endpoints]) {
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

  if (droppedTags.isNotEmpty) {
    for (var i = 0; i < outbounds.length; i++) {
      final refs = outbounds[i]['outbounds'];
      if (refs is! List) continue;
      final kept = _tagList(refs).where((t) => !droppedTags.contains(t)).toList();
      outbounds[i] = Map<String, dynamic>.from(outbounds[i])..['outbounds'] = kept;
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
    return const TikNetMergedConfigResult(configJson: '', mainGroupTag: kCoreSelectorTag, nodes: []);
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
  if (endpoints.isNotEmpty) {
    config['endpoints'] = endpoints;
  } else {
    config.remove('endpoints');
  }
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

/// True when an outbound tag was assigned by [mergeTikNetConfigs] for a catalog server.
bool isTikNetCatalogOutboundTag(String tag) => RegExp(r'^cat-\d+-').hasMatch(tag.trim());

/// Catalog id embedded in a merged tag like `cat-12-turkey`.
int? catalogIdFromOutboundTag(String? tag) {
  final m = RegExp(r'^cat-(\d+)-').firstMatch((tag ?? '').trim());
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// Removes catalog (emergency free) leaf outbounds from a merged sing-box JSON profile.
///
/// Returns `null` when [raw] is not JSON or already has no catalog tags.
String? stripCatalogOutboundsFromConfig(String raw) {
  final map = _parseSingboxMap(raw);
  if (map == null) return null;

  final outs = _sectionMaps(map, 'outbounds');
  final drop = <String>{
    for (final o in outs)
      if (isTikNetCatalogOutboundTag((o['tag'] as String?) ?? '')) (o['tag'] as String).trim(),
  };
  if (drop.isEmpty) return null;

  final kept = <Map<String, dynamic>>[];
  for (final o in outs) {
    final tag = (o['tag'] as String?)?.trim() ?? '';
    if (drop.contains(tag)) continue;
    final type = _typeOf(o);
    if (type == 'selector' || type == 'urltest' || type == 'balancer') {
      final neu = Map<String, dynamic>.from(o);
      final refs = _tagList(neu['outbounds']).where((t) => !drop.contains(t)).toList();
      neu['outbounds'] = refs;
      final def = neu['default']?.toString().trim();
      if (def != null && def.isNotEmpty && drop.contains(def)) {
        neu['default'] = refs.isNotEmpty ? refs.first : null;
      }
      kept.add(neu);
    } else {
      kept.add(Map<String, dynamic>.from(o));
    }
  }

  map['outbounds'] = kept;
  return const JsonEncoder.withIndent('  ').convert(map);
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
    } else if (decoded is List) {
      // Some panels return a bare outbounds array.
      map = {'outbounds': decoded};
    }
  } catch (_) {
    return const [];
  }
  if (map == null) return const [];

  // Single outbound object (no wrapping "outbounds" list).
  if (_outboundsList(map).isEmpty && map['type'] is String && map['tag'] is String) {
    map = {
      'outbounds': [Map<String, dynamic>.from(map)],
    };
  }

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
    if (isUnroutableOutbound(o)) continue;
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

List<Map<String, dynamic>> _sectionMaps(Map<String, dynamic> config, String key) {
  final raw = config[key];
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

/// Outbounds plus endpoints (WireGuard lives under endpoints in sing-box 1.11+).
List<Map<String, dynamic>> _outboundsList(Map<String, dynamic> config) {
  final out = <Map<String, dynamic>>[..._sectionMaps(config, 'outbounds')];
  final seen = {for (final o in out) (o['tag'] as String?)?.trim() ?? ''};
  for (final o in _sectionMaps(config, 'endpoints')) {
    final tag = (o['tag'] as String?)?.trim() ?? '';
    if (tag.isNotEmpty && seen.contains(tag)) continue;
    if (tag.isNotEmpty) seen.add(tag);
    out.add(o);
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
  final remarks = (o['remarks'] as String?)?.trim();
  if (remarks != null && remarks.isNotEmpty) return stripHiddifyTagSuffix(remarks);
  final name = (o['name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return stripHiddifyTagSuffix(name);
  return stripHiddifyTagSuffix(tag);
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
