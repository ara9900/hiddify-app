import 'package:flutter/material.dart';

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
    this.healthStatus,
    this.latencyMs,
  });

  final int id;
  final String name;
  final String countryCode;
  final String tier;
  final String sourceType;
  final bool requiresPaid;
  final bool accessible;
  final int sortOrder;
  final String? healthStatus;
  final int? latencyMs;

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
      healthStatus: json['health_status'] as String?,
      latencyMs: (json['latency_ms'] as num?)?.toInt(),
    );
  }

  bool get isHealthDown => healthStatus == 'down';

  bool get hasPing => latencyMs != null && latencyMs! > 0;

  String get pingLabel {
    if (hasPing) return '${latencyMs} ms';
    return switch (healthStatus) {
      'up' => 'آنلاین',
      'down' => 'آفلاین',
      'unknown' => '—',
      _ => '—',
    };
  }

  /// Green / yellow / red / grey for ping chip.
  Color get pingColor {
    if (isHealthDown) return const Color(0xFFEF4444);
    if (!hasPing) return const Color(0xFF9E9E9E);
    final ms = latencyMs!;
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
  });

  final bool personalAvailable;
  final List<TikNetServerEntry> servers;

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

  TikNetServerCatalog mergeHealth(List<Map<String, dynamic>> healthRows) {
    if (healthRows.isEmpty) return this;
    final byId = <int, Map<String, dynamic>>{};
    for (final row in healthRows) {
      final id = (row['id'] as num?)?.toInt();
      if (id != null) byId[id] = row;
    }
    final merged = servers.map((s) {
      final h = byId[s.id];
      if (h == null) return s;
      return TikNetServerEntry(
        id: s.id,
        name: s.name,
        countryCode: s.countryCode,
        tier: s.tier,
        sourceType: s.sourceType,
        requiresPaid: s.requiresPaid,
        accessible: s.accessible,
        sortOrder: s.sortOrder,
        healthStatus: (h['health_status'] as String?) ?? s.healthStatus,
        latencyMs: (h['latency_ms'] as num?)?.toInt() ?? s.latencyMs,
      );
    }).toList();
    return TikNetServerCatalog(personalAvailable: personalAvailable, servers: merged);
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
    this.isHealthDown = false,
  });

  final String title;
  final String subtitle;
  final String? countryCode;
  final bool personal;
  final String? pingLabel;
  final Color? pingColor;
  final bool isHealthDown;
}

TikNetSelectedServerInfo resolveSelectedServerInfo({
  required TikNetServerSelection selected,
  TikNetServerCatalog? catalog,
}) {
  if (selected.isPersonal || selected.catalogId == null) {
    return const TikNetSelectedServerInfo(
      title: 'اشتراک من',
      subtitle: 'کانفیگ اختصاصی حساب شما',
      personal: true,
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
      isHealthDown: match.isHealthDown,
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
