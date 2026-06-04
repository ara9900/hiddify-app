import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/tiknet/service/sync_service.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';

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
      if (tikNetMode) {
        TikNetDiagnosticLog.i('auth', 'login ok', {
          'panel': baseUrl,
          'user': username.trim(),
          'has_sub_url': (subscriptionUrl ?? '').isNotEmpty,
        });
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final message = _messageForStatus(statusCode, e.type);
      if (tikNetMode) {
        TikNetDiagnosticLog.w('auth', 'login failed', {'status': statusCode, 'type': e.type.name});
      }
      throw AuthException(message);
    } catch (e) {
      if (e is AuthException) rethrow;
      if (tikNetMode) TikNetDiagnosticLog.e('auth', 'login error', {'error': e.toString()});
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

  /// True when a panel access token is stored (not offline profile cache alone).
  bool hasAppSession() => _ref.read(Preferences.tikNetAccessToken).isNotEmpty;

  bool _isSessionExpired() {
    if (_ref.read(Preferences.tikNetAccessToken).isEmpty) return true;
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

  /// Clears panel URL, token, expires_at, subscription_url, sync cache, and VPN profile.
  Future<void> logout() async {
    await _ref.read(connectionNotifierProvider.notifier).abortConnection();
    await _ref.read(Preferences.startedByUser.notifier).update(false);

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
    await _ref.read(Preferences.tikNetSavedUsername.notifier).update('');
    await _ref.read(Preferences.tikNetSelectedServer.notifier).update('personal');
    await _ref.read(Preferences.tikNetCachedAnnouncement.notifier).update('');

    try {
      final repo = await _ref.read(profileRepositoryProvider.future);
      final listResult = await repo.watchAll().first;
      await listResult.fold((_) async {}, (profiles) async {
        for (final p in profiles) {
          if (p.userOverride?.name == tikNetProfileDisplayName || p.name == tikNetProfileDisplayName) {
            await repo.deleteById(p.id, p.active).run();
          }
        }
      });
    } catch (_) {}
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref));
