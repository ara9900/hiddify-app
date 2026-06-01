import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'config_service.dart';

/// Thrown when login fails (validation or API error). [message] is user-facing (e.g. Persian).
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Default app session length (also extended on each successful API call).
const Duration tikNetSessionLifetime = Duration(days: 30);

/// TikNet auth: login via panel API, token/subscription in SharedPreferences, helpers and logout.
class AuthService {
  AuthService(this._ref);
  final Ref _ref;

  static const Duration _loginTimeout = Duration(seconds: 15);

  /// POST /api/customer/login using panel URL from [ConfigService]. Saves token, expires_at, subscription_url.
  Future<void> login(String username, String password, {String? panelBaseUrl}) async {
    final configService = _ref.read(configServiceProvider);
    final resolved = panelBaseUrl?.trim();
    final baseUrl = (resolved != null && resolved.isNotEmpty)
        ? resolved.replaceAll(RegExp(r'/+$'), '')
        : await configService.getFirstWorkingPanelUrl();
    if (baseUrl.isEmpty) {
      throw AuthException('اتصال به سرور ممکن نیست');
    }

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      connectTimeout: _loginTimeout,
      sendTimeout: _loginTimeout,
      receiveTimeout: _loginTimeout,
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));

    try {
      final response = await dio.post<Map<String, dynamic>>(
        'api/customer/login',
        data: {'username': username.trim(), 'password': password},
      );
      final data = response.data;
      if (data == null) throw AuthException('پاسخ خالی از سرور');

      final accessToken = data['access_token'] as String? ?? '';
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 0;
      final subscriptionUrl = data['subscription_url'] as String?;

      if (accessToken.isEmpty) {
        throw AuthException('پاسخ سرور نامعتبر است');
      }

      final serverExpiry = expiresIn > 0 ? DateTime.now().add(Duration(seconds: expiresIn)) : null;
      final clientExpiry = DateTime.now().add(tikNetSessionLifetime);
      final expiresAt = _laterExpiry(serverExpiry, clientExpiry);

      await _ref.read(Preferences.tikNetPanelBaseUrl.notifier).update(baseUrl);
      await _ref.read(Preferences.tikNetAccessToken.notifier).update(accessToken);
      await _ref.read(Preferences.tikNetTokenExpiresAt.notifier).update(expiresAt);
      await _ref.read(Preferences.tikNetSubscriptionUrl.notifier).update(subscriptionUrl ?? '');
      await _ref.read(Preferences.tikNetSavedUsername.notifier).update(username.trim());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final message = _messageForStatus(statusCode, e.type);
      throw AuthException(message);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('اتصال به سرور ممکن نیست');
    }
  }

  String _messageForStatus(int? statusCode, DioExceptionType type) {
    if (statusCode != null) {
      switch (statusCode) {
        case 400:
          return 'نام کاربری یا رمز خالی است';
        case 401:
          return 'نام کاربری یا رمز اشتباه است';
        case 403:
          return 'این حساب مشتری نیست';
        case 429:
          return 'لطفاً یک دقیقه صبر کنید';
      }
    }
    return 'اتصال به سرور ممکن نیست';
  }

  DateTime? _laterExpiry(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// True if token is present and session not expired (client-side).
  bool isLoggedIn() => hasAppSession() && !_isSessionExpired();

  /// Stay in app when token exists (even if panel unreachable / another VPN is on).
  bool hasAppSession() {
    if (_ref.read(Preferences.tikNetAccessToken).isNotEmpty) return true;
    return _ref.read(Preferences.tikNetCachedProfile).isNotEmpty;
  }

  bool _isSessionExpired() {
    final token = _ref.read(Preferences.tikNetAccessToken);
    if (token.isEmpty) return _ref.read(Preferences.tikNetCachedProfile).isEmpty;
    final expiresAt = _ref.read(Preferences.tikNetTokenExpiresAt);
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt);
  }

  /// Sliding session — call after successful authenticated API requests.
  Future<void> extendSession() async {
    if (_ref.read(Preferences.tikNetAccessToken).isEmpty) return;
    await _ref.read(Preferences.tikNetTokenExpiresAt.notifier).update(
          DateTime.now().add(tikNetSessionLifetime),
        );
  }

  /// Returns true if session was cleared (user must log in again).
  /// Does NOT logout on 401 when session is still valid locally (VPN glitch / offline).
  Future<bool> clearSessionIfUnauthorized() async {
    if (!_isSessionExpired()) return false;
    await logout();
    return true;
  }

  String getToken() => _ref.read(Preferences.tikNetAccessToken);

  String getSavedUsername() => _ref.read(Preferences.tikNetSavedUsername);

  /// Returns subscription URL or null if not set.
  String? getSubscriptionUrl() {
    final url = _ref.read(Preferences.tikNetSubscriptionUrl);
    return url.isEmpty ? null : url;
  }

  /// Clears panel URL, token, expires_at, subscription_url, and sync cache.
  Future<void> logout() async {
    final baseUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    final token = _ref.read(Preferences.tikNetAccessToken);
    if (baseUrl.isNotEmpty && token.isNotEmpty) {
      await _ref.read(tikNetApiProvider).logoutRemote(baseUrl: baseUrl, accessToken: token);
    }
    await _ref.read(Preferences.tikNetPanelBaseUrl.notifier).update('');
    await _ref.read(Preferences.tikNetAccessToken.notifier).update('');
    await _ref.read(Preferences.tikNetTokenExpiresAt.notifier).update(null);
    await _ref.read(Preferences.tikNetSubscriptionUrl.notifier).update('');
    await _ref.read(Preferences.tikNetCachedProfile.notifier).update('');
    await _ref.read(Preferences.tikNetCachedConfig.notifier).update('');
    await _ref.read(Preferences.tikNetProfileId.notifier).update('');
    await _ref.read(Preferences.tikNetLastSyncTime.notifier).update(null);
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref));
