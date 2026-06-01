/// Reseller / panel branding from GET /api/customer/me → brand.
class TikNetBrand {
  const TikNetBrand({
    this.name,
    this.logoUrl,
    this.primaryColor,
    this.supportTelegram,
    this.apiBaseUrl,
  });

  final String? name;
  final String? logoUrl;
  final String? primaryColor;
  final String? supportTelegram;
  final String? apiBaseUrl;

  factory TikNetBrand.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TikNetBrand();
    return TikNetBrand(
      name: (json['name'] as String?)?.trim(),
      logoUrl: (json['logo_url'] as String?)?.trim(),
      primaryColor: (json['primary_color'] as String?)?.trim(),
      supportTelegram: (json['support_telegram'] as String?)?.trim(),
      apiBaseUrl: (json['api_base_url'] as String?)?.trim(),
    );
  }

  bool get isEmpty =>
      (name == null || name!.isEmpty) &&
      (logoUrl == null || logoUrl!.isEmpty) &&
      (supportTelegram == null || supportTelegram!.isEmpty);
}
