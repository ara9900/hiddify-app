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

  String get healthLabel {
    if (latencyMs != null && latencyMs! > 0) return '${latencyMs}ms';
    return switch (healthStatus) {
      'up' => 'آنلاین',
      'down' => 'آفلاین',
      _ => '',
    };
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
