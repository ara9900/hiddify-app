import 'package:flutter/material.dart';

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
      TikNetClientPingState.unreachable => 'فیلتر/قطع',
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
  });

  final bool personalAvailable;
  final List<TikNetServerEntry> servers;
  final TikNetClientPingResult? personalPing;

  factory TikNetServerCatalog.fromJson(Map<String, dynamic> json) {
    final list = json['servers'];
    return TikNetServerCatalog(
      personalAvailable: json['personal_available'] as bool? ?? false,
      servers: list is List
          ? list
              .whereType<Map>()
              .map((e) => TikNetServerEntry.fromJson(Map<String, dynamic>.from(e)))
              .where((s) => s.id > 0)
              .toList()
          : const [],
    );
  }

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
}) {
  if (selected.isPersonal || selected.catalogId == null) {
    final personal = catalog?.personalPing;
    return TikNetSelectedServerInfo(
      title: 'اشتراک من',
      subtitle: 'کانفیگ اختصاصی حساب شما',
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

typedef TikNetServerSelection = ({bool isPersonal, int? catalogId});

TikNetServerSelection parseServerSelection(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t == 'personal') return (isPersonal: true, catalogId: null);
  final id = int.tryParse(t);
  if (id != null && id > 0) return (isPersonal: false, catalogId: id);
  return (isPersonal: true, catalogId: null);
}

String encodeServerSelection(TikNetServerSelection sel) {
  if (sel.isPersonal || sel.catalogId == null) return 'personal';
  return '${sel.catalogId}';
}
