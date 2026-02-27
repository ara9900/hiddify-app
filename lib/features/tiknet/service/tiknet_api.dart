import 'package:dio/dio.dart';
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
  });
  final String username;
  final String? fullName;
  final DateTime? expireDate;
  final bool hasSubscription;

  factory TikNetUserInfo.fromJson(Map<String, dynamic> json) {
    String? expireStr = json['expire_date'] as String?;
    return TikNetUserInfo(
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String?,
      expireDate: expireStr != null ? DateTime.tryParse(expireStr) : null,
      hasSubscription: json['has_subscription'] as bool? ?? false,
    );
  }
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
}

