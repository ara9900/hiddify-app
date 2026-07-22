import 'dart:convert';

import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';

String encodeTikNetNodeMeta(List<TikNetPersonalProxyNode> nodes) {
  final list = nodes
      .map(
        (n) => {
          'tag': n.tag,
          'label': n.label,
          'source': n.source.name,
          if (n.catalogId != null) 'catalog_id': n.catalogId,
          'group': n.groupTag,
        },
      )
      .toList();
  return jsonEncode(list);
}

Map<String, TikNetPersonalProxyNode> decodeTikNetNodeMeta(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    final map = <String, TikNetPersonalProxyNode>{};
    for (final e in decoded) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final tag = (m['tag'] as String?)?.trim() ?? '';
      if (tag.isEmpty) continue;
      final sourceName = (m['source'] as String?)?.trim() ?? 'subscription';
      final source = sourceName == 'catalog' ? TikNetNodeSource.catalog : TikNetNodeSource.subscription;
      map[tag] = TikNetPersonalProxyNode(
        tag: tag,
        groupTag: (m['group'] as String?)?.trim() ?? 'Select',
        label: (m['label'] as String?)?.trim().isNotEmpty == true ? (m['label'] as String).trim() : tag,
        source: source,
        catalogId: (m['catalog_id'] as num?)?.toInt(),
      );
    }
    return map;
  } catch (_) {
    return const {};
  }
}

/// Prefer meta labels/source; fall back to tag heuristics (`cat-{id}-…`).
List<TikNetPersonalProxyNode> applyNodeMeta(
  List<TikNetPersonalProxyNode> parsed,
  Map<String, TikNetPersonalProxyNode> meta,
) {
  return parsed.map((n) {
    final m = meta[n.tag];
    if (m != null) {
      return TikNetPersonalProxyNode(
        tag: n.tag,
        groupTag: m.groupTag.isNotEmpty ? m.groupTag : n.groupTag,
        label: m.label,
        probeUrl: n.probeUrl,
        source: m.source,
        catalogId: m.catalogId,
      );
    }
    final inferred = _inferFromTag(n.tag);
    if (inferred == null) return n;
    return TikNetPersonalProxyNode(
      tag: n.tag,
      groupTag: n.groupTag,
      label: n.label,
      probeUrl: n.probeUrl,
      source: inferred.source,
      catalogId: inferred.catalogId,
    );
  }).toList();
}

({TikNetNodeSource source, int? catalogId})? _inferFromTag(String tag) {
  final m = RegExp(r'^cat-(\d+)-').firstMatch(tag);
  if (m == null) return null;
  final id = int.tryParse(m.group(1)!);
  return (source: TikNetNodeSource.catalog, catalogId: id);
}
