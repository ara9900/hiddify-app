import 'dart:convert';

/// Parsed QR / deep-link payload for TikNet login.
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

/// One-time login token from Telegram bot / panel deep link.
class TikNetQrLoginToken extends TikNetQrLoginPayload {
  const TikNetQrLoginToken({
    required this.token,
    this.panelUrl,
  });

  final String token;
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

  // JSON: {"username":"...","password":"..."} or {"token":"..."} optional panel_url
  if (text.startsWith('{')) {
    try {
      final map = jsonDecode(text) as Map<String, dynamic>;
      final token = (map['token'] ?? map['login_token'])?.toString().trim() ?? '';
      final panel = (map['panel_url'] ?? map['panel'] ?? map['base_url'])?.toString().trim();
      if (token.isNotEmpty) {
        return TikNetQrLoginToken(token: token, panelUrl: panel?.isNotEmpty == true ? panel : null);
      }
      final user = (map['username'] ?? map['user'] ?? map['u'])?.toString().trim() ?? '';
      final pass = (map['password'] ?? map['pass'] ?? map['p'])?.toString() ?? '';
      if (user.isNotEmpty && pass.isNotEmpty) {
        return TikNetQrCredentials(username: user, password: pass, panelUrl: panel?.isNotEmpty == true ? panel : null);
      }
    } catch (_) {}
  }

  final uri = Uri.tryParse(text);

  // tiknet://login?token=... or ?username=&password=
  if (uri != null && uri.scheme == 'tiknet') {
    final token = (uri.queryParameters['token'] ?? uri.queryParameters['login_token'] ?? '').trim();
    final panel = uri.queryParameters['panel'] ?? uri.queryParameters['panel_url'];
    if (token.isNotEmpty) {
      return TikNetQrLoginToken(token: token, panelUrl: panel?.trim());
    }
    final user = (uri.queryParameters['username'] ?? uri.queryParameters['user'] ?? '').trim();
    final pass = uri.queryParameters['password'] ?? uri.queryParameters['pass'] ?? '';
    if (user.isNotEmpty && pass.isNotEmpty) {
      return TikNetQrCredentials(username: user, password: pass, panelUrl: panel?.trim());
    }
  }

  // HTTPS panel fallback: https://host/app/login?token=...
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final path = uri.path.toLowerCase();
    final token = (uri.queryParameters['token'] ?? uri.queryParameters['login_token'] ?? '').trim();
    if (token.isNotEmpty && (path.contains('/app/login') || path.endsWith('/login'))) {
      final panel = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      return TikNetQrLoginToken(token: token, panelUrl: panel);
    }
    return TikNetQrSubscriptionLink(text);
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

  return null;
}

/// True when [link] is a TikNet login deep link (not a profile import).
bool isTikNetLoginDeepLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null) return false;
  if (uri.scheme == 'tiknet') return true;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    final path = uri.path.toLowerCase();
    final token = (uri.queryParameters['token'] ?? '').trim();
    return token.isNotEmpty && (path.contains('/app/login') || path.endsWith('/login'));
  }
  return false;
}
