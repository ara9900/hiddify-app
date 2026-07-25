/// Public bootstrap from GET /api/customer/public-config (no auth).
class TikNetPublicConfig {
  const TikNetPublicConfig({
    this.telegramShopEnabled = false,
    this.telegramShopUrl,
    this.telegramShopLabel,
  });

  final bool telegramShopEnabled;
  final String? telegramShopUrl;
  final String? telegramShopLabel;

  factory TikNetPublicConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TikNetPublicConfig();
    final url = (json['telegram_shop_url'] as String?)?.trim();
    return TikNetPublicConfig(
      telegramShopEnabled: json['telegram_shop_enabled'] as bool? ?? false,
      telegramShopUrl: (url != null && url.isNotEmpty) ? url : null,
      telegramShopLabel: (json['telegram_shop_label'] as String?)?.trim(),
    );
  }

  bool get showTelegramShop {
    if (!telegramShopEnabled) return false;
    final url = telegramShopUrl;
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'tg');
  }
}
