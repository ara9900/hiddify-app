import 'dart:convert';

/// Parsed QR payload for TikNet login.
sealed class TikNetQrLoginPayload {
  const TikNetQrLoginPayload();
}

class TikNetQrCredentials extends TikNetQrLoginPayload {
  const TikNetQrCredentials({
    required this.username,
    required this.password,
    this.panelUrl,
  });

  final String username;
  final String password;
  final String? panelUrl;
}

/// Subscription / config link (panel QR ساب). Needs username/password for full panel login.
class TikNetQrSubscriptionLink extends TikNetQrLoginPayload {
  const TikNetQrSubscriptionLink(this.url);
  final String url;
}

TikNetQrLoginPayload? parseTikNetQrLogin(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // JSON: {"username":"...","password":"..."} optional panel_url
  if (text.startsWith('{')) {
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final user = (map['username'] ?? map['user'] ?? map['u'])?.toString().trim() ?? '';
      final pass = (map['password'] ?? map['pass'] ?? map['p'])?.toString() ?? '';
      final panel = (map['panel_url'] ?? map['panel'] ?? map['base_url'])?.toString().trim();
      if (user.isNotEmpty && pass.isNotEmpty) {
        return TikNetQrCredentials(username: user, password: pass, panelUrl: panel?.isNotEmpty == true ? panel : null);
      }
    } catch (_) {}
  }

  // tiknet://login?username=x&password=y
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme == 'tiknet') {
    final user = (uri.queryParameters['username'] ?? uri.queryParameters['user'] ?? '').trim();
    final pass = uri.queryParameters['password'] ?? uri.queryParameters['pass'] ?? '';
    final panel = uri.queryParameters['panel'] ?? uri.queryParameters['panel_url'];
    if (user.isNotEmpty && pass.isNotEmpty) {
      return TikNetQrCredentials(username: user, password: pass, panelUrl: panel?.trim());
    }
  }

  // username:password (single line)
  final colon = text.indexOf(':');
  if (colon > 0 && colon < text.length - 1 && !text.startsWith('http')) {
    final user = text.substring(0, colon).trim();
    final pass = text.substring(colon + 1);
    if (user.isNotEmpty && pass.isNotEmpty && !user.contains(' ')) {
      return TikNetQrCredentials(username: user, password: pass);
    }
  }

  // Panel subscription QR (http/https)
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return TikNetQrSubscriptionLink(text);
  }

  return null;
}
