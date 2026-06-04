import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';

import 'package:hiddify/features/tiknet/model/personal_outbound_catalog.dart';

/// Client-side reachability from the user's device (ISP / region).
enum TikNetClientPingState {
  measuring,
  noTarget,
  reachable,
  unreachable,
}

class TikNetClientPingResult {
  const TikNetClientPingResult({
    required this.state,
    this.pingMs,
  });

  final TikNetClientPingState state;
  final int? pingMs;

  bool get reachable => state == TikNetClientPingState.reachable;

  String get pingLabel {
    return switch (state) {
      TikNetClientPingState.measuring => '…',
      TikNetClientPingState.noTarget => '—',
      TikNetClientPingState.reachable when pingMs != null && pingMs! > 0 => '$pingMs ms',
      TikNetClientPingState.reachable => 'در دسترس',
      TikNetClientPingState.unreachable => 'قطع',
    };
  }

  Color get pingColor {
    return switch (state) {
      TikNetClientPingState.measuring => const Color(0xFF9E9E9E),
      TikNetClientPingState.noTarget => const Color(0xFF9E9E9E),
      TikNetClientPingState.unreachable => const Color(0xFFEF4444),
      TikNetClientPingState.reachable => _latencyColor(pingMs ?? 0),
    };
  }

  static Color _latencyColor(int ms) {
    if (ms <= 0) return const Color(0xFF22C55E);
    if (ms <= 120) return const Color(0xFF22C55E);
    if (ms <= 250) return const Color(0xFFEAB308);
    return const Color(0xFFF97316);
  }
}

/// Catalog server entry from panel GET /api/customer/servers
class TikNetServerEntry {
  const TikNetServerEntry({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.tier,
    required this.sourceType,
    required this.requiresPaid,
    required this.accessible,
    required this.sortOrder,
    this.probeUrl = '',
    this.clientPingState = TikNetClientPingState.measuring,
    this.clientPingMs,
  });

  final int id;
  final String name;
  final String countryCode;
  final String tier;
  final String sourceType;
  final bool requiresPaid;
  final bool accessible;
  final int sortOrder;
  final String probeUrl;
  final TikNetClientPingState clientPingState;
  final int? clientPingMs;

  factory TikNetServerEntry.fromJson(Map<String, dynamic> json) {
    return TikNetServerEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      countryCode: ((json['country_code'] as String?) ?? '').toUpperCase(),
      tier: (json['tier'] as String?) ?? 'free',
      sourceType: (json['source_type'] as String?) ?? 'subscription',
      requiresPaid: json['requires_paid'] as bool? ?? false,
      accessible: json['accessible'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      probeUrl: (json['probe_url'] as String?)?.trim() ?? '',
    );
  }

  TikNetServerEntry copyWithClientPing({
    required TikNetClientPingState state,
    int? pingMs,
  }) {
    return TikNetServerEntry(
      id: id,
      name: name,
      countryCode: countryCode,
      tier: tier,
      sourceType: sourceType,
      requiresPaid: requiresPaid,
      accessible: accessible,
      sortOrder: sortOrder,
      probeUrl: probeUrl,
      clientPingState: state,
      clientPingMs: pingMs,
    );
  }

  bool get isUnreachableFromDevice => clientPingState == TikNetClientPingState.unreachable;

  bool get hasClientPing => clientPingState == TikNetClientPingState.reachable &&
      clientPingMs != null &&
      clientPingMs! > 0;

  String get pingLabel {
    if (clientPingState == TikNetClientPingState.measuring) return '…';
    if (clientPingState == TikNetClientPingState.noTarget) return '—';
    if (clientPingState == TikNetClientPingState.unreachable) return 'فیلتر/قطع';
    if (hasClientPing) return '$clientPingMs ms';
    if (clientPingState == TikNetClientPingState.reachable) return 'در دسترس';
    return '—';
  }

  Color get pingColor {
    if (clientPingState == TikNetClientPingState.measuring) {
      return const Color(0xFF9E9E9E);
    }
    if (clientPingState == TikNetClientPingState.noTarget) {
      return const Color(0xFF9E9E9E);
    }
    if (clientPingState == TikNetClientPingState.unreachable) {
      return const Color(0xFFEF4444);
    }
    final ms = clientPingMs ?? 0;
    if (ms <= 0) return const Color(0xFF22C55E);
    if (ms <= 120) return const Color(0xFF22C55E);
    if (ms <= 250) return const Color(0xFFEAB308);
    return const Color(0xFFF97316);
  }

  String get tierLabel => switch (tier) {
        'vip' => 'VIP',
        'normal' => 'معمولی',
        _ => 'رایگان',
      };

  String get countryLabel {
    if (countryCode.isEmpty) return '';
    return switch (countryCode) {
      'DE' => 'آلمان',
      'FR' => 'فرانسه',
      'NL' => 'هلند',
      'US' => 'آمریکا',
      'GB' => 'انگلیس',
      'TR' => 'ترکیه',
      'AE' => 'امارات',
      _ => countryCode,
    };
  }
}

class TikNetServerCatalog {
  const TikNetServerCatalog({
    required this.personalAvailable,
    required this.servers,
    this.personalPing,
    this.displayMode = TikNetServerDisplayMode.both,
  });

  final bool personalAvailable;
  final List<TikNetServerEntry> servers;
  final TikNetClientPingResult? personalPing;
  final TikNetServerDisplayMode displayMode;

  factory TikNetServerCatalog.fromJson(Map<String, dynamic> json) {
    final list = json['servers'];
    return TikNetServerCatalog(
      personalAvailable: json['personal_available'] as bool? ?? false,
      displayMode: TikNetServerDisplayMode.fromApi(json['display_mode'] as String?),
      servers: list is List
          ? list
              .whereType<Map>()
              .map((e) => TikNetServerEntry.fromJson(Map<String, dynamic>.from(e)))
              .where((s) => s.id > 0)
              .toList()
          : const [],
    );
  }

  bool get showPersonal => personalAvailable && displayMode != TikNetServerDisplayMode.catalogOnly;

  bool get showCatalog => displayMode != TikNetServerDisplayMode.personalOnly && servers.isNotEmpty;

  Map<String, List<TikNetServerEntry>> groupedByTier() {
    final map = <String, List<TikNetServerEntry>>{};
    for (final s in servers) {
      map.putIfAbsent(s.tier, () => []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return map;
  }
}

/// Resolved label for current server selection.
class TikNetSelectedServerInfo {
  const TikNetSelectedServerInfo({
    required this.title,
    required this.subtitle,
    this.countryCode,
    this.personal = false,
    this.pingLabel,
    this.pingColor,
    this.isUnreachableFromDevice = false,
  });

  final String title;
  final String subtitle;
  final String? countryCode;
  final bool personal;
  final String? pingLabel;
  final Color? pingColor;
  final bool isUnreachableFromDevice;
}

TikNetSelectedServerInfo resolveSelectedServerInfo({
  required TikNetServerSelection selected,
  TikNetServerCatalog? catalog,
  TikNetPersonalOutboundCatalog? personalCatalog,
  Map<String, TikNetClientPingResult>? personalNodePings,
}) {
  if (selected.isPersonal && selected.catalogId == null) {
    if (selected.personalKind == TikNetPersonalPickKind.urltest ||
        selected.personalKind == TikNetPersonalPickKind.balancer) {
      final mode = personalCatalog?.autoModes
          .where((m) => m.tag == selected.personalTag && m.kind == selected.personalKind)
          .firstOrNull;
      if (mode != null) {
        return TikNetSelectedServerInfo(
          title: mode.title,
          subtitle: mode.subtitle,
          personal: true,
        );
      }
    }
    if (selected.personalKind == TikNetPersonalPickKind.proxy &&
        selected.personalTag != null &&
        selected.personalTag!.isNotEmpty) {
      final node = personalCatalog?.nodes.where((n) => n.tag == selected.personalTag).firstOrNull;
      final ping = personalNodePings?[selected.personalTag!];
      return TikNetSelectedServerInfo(
        title: node?.label ?? selected.personalTag!,
        subtitle: 'اشتراک اختصاصی',
        personal: true,
        pingLabel: ping?.pingLabel,
        pingColor: ping?.pingColor,
        isUnreachableFromDevice: ping?.state == TikNetClientPingState.unreachable,
      );
    }
    final personal = catalog?.personalPing;
    return TikNetSelectedServerInfo(
      title: 'اشتراک من',
      subtitle: 'پیش‌فرض کانفیگ اشتراک',
      personal: true,
      pingLabel: personal?.pingLabel,
      pingColor: personal?.pingColor,
      isUnreachableFromDevice: personal?.state == TikNetClientPingState.unreachable,
    );
  }
  TikNetServerEntry? match;
  for (final s in catalog?.servers ?? const <TikNetServerEntry>[]) {
    if (s.id == selected.catalogId) {
      match = s;
      break;
    }
  }
  if (match != null) {
    final parts = <String>[match.countryLabel, match.tierLabel].where((e) => e.isNotEmpty);
    return TikNetSelectedServerInfo(
      title: match.name,
      subtitle: parts.join(' · '),
      countryCode: match.countryCode,
      pingLabel: match.pingLabel,
      pingColor: match.pingColor,
      isUnreachableFromDevice: match.isUnreachableFromDevice,
    );
  }
  return TikNetSelectedServerInfo(
    title: 'سرور #${selected.catalogId}',
    subtitle: 'کاتالوگ',
  );
}

typedef TikNetServerSelection = ({
  bool isPersonal,
  int? catalogId,
  TikNetPersonalPickKind personalKind,
  String? personalTag,
  String? personalGroupTag,
});

TikNetServerSelection personalDefaultSelection() => (
      isPersonal: true,
      catalogId: null,
      personalKind: TikNetPersonalPickKind.defaultAuto,
      personalTag: null,
      personalGroupTag: null,
    );

TikNetServerSelection parseServerSelection(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t == 'personal') return personalDefaultSelection();

  if (t.startsWith('cat:')) {
    final id = int.tryParse(t.substring(4));
    if (id != null && id > 0) {
      return (
        isPersonal: false,
        catalogId: id,
        personalKind: TikNetPersonalPickKind.defaultAuto,
        personalTag: null,
        personalGroupTag: null,
      );
    }
  }

  final id = int.tryParse(t);
  if (id != null && id > 0) {
    return (
      isPersonal: false,
      catalogId: id,
      personalKind: TikNetPersonalPickKind.defaultAuto,
      personalTag: null,
      personalGroupTag: null,
    );
  }

  if (t.startsWith('p:')) {
    final parts = t.split(':');
    if (parts.length >= 3) {
      final kindKey = parts[1];
      if (kindKey == 'u' && parts.length >= 3) {
        return (
          isPersonal: true,
          catalogId: null,
          personalKind: TikNetPersonalPickKind.urltest,
          personalTag: parts[2],
          personalGroupTag: parts.length >= 4 ? parts[3] : null,
        );
      }
      if (kindKey == 'b' && parts.length >= 3) {
        return (
          isPersonal: true,
          catalogId: null,
          personalKind: TikNetPersonalPickKind.balancer,
          personalTag: parts[2],
          personalGroupTag: parts.length >= 4 ? parts[3] : null,
        );
      }
      if (kindKey == 'n' && parts.length >= 4) {
        return (
          isPersonal: true,
          catalogId: null,
          personalKind: TikNetPersonalPickKind.proxy,
          personalTag: parts[3],
          personalGroupTag: parts[2],
        );
      }
    }
  }

  return personalDefaultSelection();
}

String encodeServerSelection(TikNetServerSelection sel) {
  if (!sel.isPersonal && sel.catalogId != null) return 'cat:${sel.catalogId}';
  if (!sel.isPersonal) return 'personal';
  switch (sel.personalKind) {
    case TikNetPersonalPickKind.urltest:
      final tag = sel.personalTag ?? '';
      final group = sel.personalGroupTag ?? '';
      return tag.isEmpty ? 'personal' : 'p:u:$tag${group.isNotEmpty ? ':$group' : ''}';
    case TikNetPersonalPickKind.balancer:
      final tag = sel.personalTag ?? '';
      final group = sel.personalGroupTag ?? '';
      return tag.isEmpty ? 'personal' : 'p:b:$tag${group.isNotEmpty ? ':$group' : ''}';
    case TikNetPersonalPickKind.proxy:
      final tag = sel.personalTag ?? '';
      final group = sel.personalGroupTag ?? '';
      if (tag.isEmpty || group.isEmpty) return 'personal';
      return 'p:n:$group:$tag';
    case TikNetPersonalPickKind.defaultAuto:
      return 'personal';
  }
}

bool selectionNeedsOutboundApply(TikNetServerSelection sel) =>
    sel.isPersonal &&
    sel.catalogId == null &&
    sel.personalKind != TikNetPersonalPickKind.defaultAuto &&
    (sel.personalTag ?? '').isNotEmpty;
