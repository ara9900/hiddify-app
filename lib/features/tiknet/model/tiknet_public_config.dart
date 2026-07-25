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

    Map<String, dynamic>? asMap(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;

    final shop = asMap(json['shop']) ?? asMap(json['buy_renew']) ?? asMap(json['app_shop']);

    bool? pickBool(Iterable<String> keys, [Map<String, dynamic>? nested]) {
      for (final k in keys) {
        final v = json[k] ?? nested?[k];
        if (v is bool) return v;
      }
      return null;
    }

    String? pickString(Iterable<String> keys, [Map<String, dynamic>? nested]) {
      for (final k in keys) {
        final v = (json[k] ?? nested?[k])?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    // Panel admin "خرید و تمدید در اپ" may use several key names.
    final enabled = pickBool(const [
          'telegram_shop_enabled',
          'shop_enabled',
          'app_shop_enabled',
          'buy_enabled',
          'buy_renew_enabled',
          'show_shop_button',
          'show_buy_button',
        ], shop) ??
        pickBool(const ['enabled'], shop) ??
        false;

    final url = pickString(const [
          'telegram_shop_url',
          'shop_url',
          'app_shop_url',
          'buy_url',
          'buy_renew_url',
          'renew_url',
          'telegram_bot_url',
        ], shop) ??
        pickString(const ['url', 'link'], shop);

    final label = pickString(const [
          'telegram_shop_label',
          'shop_label',
          'buy_label',
          'buy_renew_label',
        ], shop) ??
        pickString(const ['label', 'title'], shop);

    return TikNetPublicConfig(
      telegramShopEnabled: enabled,
      telegramShopUrl: url,
      telegramShopLabel: label,
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
