import 'package:dio/dio.dart';
import 'package:hiddify/features/tiknet/model/tiknet_brand.dart';
import 'package:hiddify/features/tiknet/model/tiknet_faq.dart';
import 'package:hiddify/features/tiknet/model/tiknet_notification.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
/// Thrown when panel returns 4xx/5xx with optional [detail] from response body.
class TikNetApiException implements Exception {
  TikNetApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Response from POST /api/customer/login
class TikNetLoginResponse {
  TikNetLoginResponse({
    required this.accessToken,
    required this.expiresIn,
    required this.subscriptionUrl,
  });
  final String accessToken;
  final int expiresIn;
  final String? subscriptionUrl;

  factory TikNetLoginResponse.fromJson(Map<String, dynamic> json) {
    return TikNetLoginResponse(
      accessToken: json['access_token'] as String? ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
      subscriptionUrl: json['subscription_url'] as String?,
    );
  }
}

/// Response from GET /api/customer/me
class TikNetUserInfo {
  TikNetUserInfo({
    required this.username,
    this.fullName,
    this.expireDate,
    required this.hasSubscription,
    this.planName,
    this.isExpired,
    this.daysRemaining,
    this.trafficUsedBytes,
    this.trafficLimitBytes,
    this.brand,
    this.shopEnabled = true,
  });
  final String username;
  final String? fullName;
  final DateTime? expireDate;
  final bool hasSubscription;
  final String? planName;
  final bool? isExpired;
  final int? daysRemaining;
  final int? trafficUsedBytes;
  final int? trafficLimitBytes;
  final TikNetBrand? brand;
  final bool shopEnabled;

  factory TikNetUserInfo.fromJson(Map<String, dynamic> json) {
    final expireStr = json['expire_date'] as String?;
    final brandRaw = json['brand'];
    return TikNetUserInfo(
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String?,
      expireDate: expireStr != null ? DateTime.tryParse(expireStr) : null,
      hasSubscription: json['has_subscription'] as bool? ?? false,
      planName: json['plan_name'] as String?,
      isExpired: json['is_expired'] as bool?,
      daysRemaining: (json['days_remaining'] as num?)?.toInt(),
      trafficUsedBytes: (json['traffic_used_bytes'] as num?)?.toInt(),
      trafficLimitBytes: (json['traffic_limit_bytes'] as num?)?.toInt(),
      brand: brandRaw is Map ? TikNetBrand.fromJson(Map<String, dynamic>.from(brandRaw)) : null,
      shopEnabled: json['shop_enabled'] as bool? ?? true,
    );
  }
}

class TikNetCustomerOrder {
  TikNetCustomerOrder({
    required this.id,
    required this.planName,
    required this.status,
    this.expireDate,
    this.trafficUsedBytes,
    this.trafficLimitBytes,
    this.renewUrl,
  });

  final int id;
  final String planName;
  final String status;
  final DateTime? expireDate;
  final int? trafficUsedBytes;
  final int? trafficLimitBytes;
  final String? renewUrl;

  factory TikNetCustomerOrder.fromJson(Map<String, dynamic> json) {
    final expireStr = json['expire_date'] as String?;
    return TikNetCustomerOrder(
      id: (json['id'] as num?)?.toInt() ?? 0,
      planName: (json['plan_name'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      expireDate: expireStr != null ? DateTime.tryParse(expireStr) : null,
      trafficUsedBytes: (json['traffic_used_bytes'] as num?)?.toInt(),
      trafficLimitBytes: (json['traffic_limit_bytes'] as num?)?.toInt(),
      renewUrl: (json['renew_url'] as String?)?.trim(),
    );
  }

  bool get isActive => status.toLowerCase() == 'active';
}

final tikNetApiProvider = Provider<TikNetApi>((ref) => TikNetApi());

class TikNetApi {
  Dio _dio(String baseUrl) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));
  }

  /// POST /api/customer/login
  Future<TikNetLoginResponse> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final dio = _dio(baseUrl);
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/api/customer/login',
        data: {'username': username.trim(), 'password': password},
      );
      if (response.data == null) throw TikNetApiException('Empty response');
      return TikNetLoginResponse.fromJson(response.data!);
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      final msg = detail is String ? detail : (e.message ?? 'Login failed');
      throw TikNetApiException(msg, statusCode: e.response?.statusCode);
    }
  }

  /// GET /api/customer/me
  Future<TikNetUserInfo> getMe({required String baseUrl, required String accessToken}) async {
    final dio = _dio(baseUrl);
    final response = await dio.get<Map<String, dynamic>>(
      '/api/customer/me',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    if (response.data == null) throw Exception('Empty response');
    return TikNetUserInfo.fromJson(response.data!);
  }

  /// POST /api/customer/logout — best effort; ignores errors.
  Future<void> logoutRemote({required String baseUrl, required String accessToken}) async {
    try {
      final dio = _dio(baseUrl);
      await dio.post<void>(
        '/api/customer/logout',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } catch (_) {}
  }

  /// GET /api/customer/faq
  Future<List<TikNetFaqItem>> getFaq({required String baseUrl}) async {
    final dio = _dio(baseUrl);
    final response = await dio.get<Map<String, dynamic>>('/api/customer/faq');
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => TikNetFaqItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0 && e.question.isNotEmpty)
        .toList();
  }

  /// GET /api/customer/orders
  Future<List<TikNetCustomerOrder>> getOrders({required String baseUrl, required String accessToken}) async {
    final dio = _dio(baseUrl);
    final response = await dio.get<Map<String, dynamic>>(
      '/api/customer/orders',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final orders = response.data?['orders'];
    if (orders is! List) return const [];
    return orders
        .whereType<Map>()
        .map((e) => TikNetCustomerOrder.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0)
        .toList();
  }

  /// GET /api/customer/notifications
  Future<TikNetInbox> getNotifications({required String baseUrl, required String accessToken}) async {
    final dio = _dio(baseUrl);
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/customer/notifications',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.data == null) return TikNetInbox.empty;
      return TikNetInbox.fromJson(response.data!);
    } catch (_) {
      return TikNetInbox.empty;
    }
  }

  /// POST /api/customer/notifications/{id}/read
  Future<void> markNotificationRead({
    required String baseUrl,
    required String accessToken,
    required int notificationId,
  }) async {
    final dio = _dio(baseUrl);
    await dio.post<void>(
      '/api/customer/notifications/$notificationId/read',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  /// POST /api/customer/device/register
  Future<void> registerDevice({
    required String baseUrl,
    required String accessToken,
    required String deviceId,
    String platform = 'android',
    String deviceModel = '',
    String appVersion = '',
    int? versionCode,
    int? androidSdk,
  }) async {
    final dio = _dio(baseUrl);
    await dio.post<void>(
      '/api/customer/device/register',
      data: {
        'device_id': deviceId,
        'platform': platform,
        'device_model': deviceModel,
        'app_version': appVersion,
        if (versionCode != null) 'version_code': versionCode,
        if (androidSdk != null) 'android_sdk': androidSdk,
      },
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  /// GET /api/customer/app-config — panel bootstrap (includes network.dns).
  Future<Map<String, dynamic>> getAppConfig({required String baseUrl, required String accessToken}) async {
    final dio = _dio(baseUrl);
    final response = await dio.get<Map<String, dynamic>>(
      '/api/customer/app-config',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    if (response.data == null) throw TikNetApiException('Empty response');
    return response.data!;
  }

  /// GET /api/customer/subscription/config - returns raw bytes
  Future<List<int>> getSubscriptionConfig({required String baseUrl, required String accessToken}) async {
    final dio = _dio(baseUrl);
    final response = await dio.get<List<int>>(
      '/api/customer/subscription/config',
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        responseType: ResponseType.bytes,
      ),
    );
    return response.data ?? [];
  }

  /// GET /api/customer/servers/health — cached ping probes (best effort).
  Future<List<Map<String, dynamic>>> getServersHealth({
    required String baseUrl,
    required String accessToken,
    bool force = false,
  }) async {
    final dio = _dio(baseUrl);
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/customer/servers/health',
        queryParameters: force ? {'force': 'true'} : null,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final servers = response.data?['servers'];
      if (servers is! List) return const [];
      return servers.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// GET /api/customer/servers
  Future<Map<String, dynamic>> getServerCatalog({required String baseUrl, required String accessToken}) async {
    final dio = _dio(baseUrl);
    final response = await dio.get<Map<String, dynamic>>(
      '/api/customer/servers',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    if (response.data == null) throw TikNetApiException('Empty response');
    return response.data!;
  }

  /// GET /api/customer/servers/{id}/config
  Future<List<int>> getServerConfig({
    required String baseUrl,
    required String accessToken,
    required int serverId,
  }) async {
    final dio = _dio(baseUrl);
    try {
      final response = await dio.get<List<int>>(
        '/api/customer/servers/$serverId/config',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          responseType: ResponseType.bytes,
        ),
      );
      return response.data ?? [];
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      final msg = detail is String ? detail : (e.message ?? 'دریافت کانفیگ سرور ناموفق');
      throw TikNetApiException(msg, statusCode: e.response?.statusCode);
    }
  }
}
