import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const String _githubConfigUrl = 'https://ara9900.github.io/app-config/config.json';
const Duration _announcementTimeout = Duration(seconds: 8);

/// پیام اعلان آنلاین: نمایش در باکس بین دکمه اتصال و کارت اطلاعات.
class AnnouncementMessage {
  AnnouncementMessage({required this.show, required this.type, required this.text});
  final bool show;
  final String type; // warning, info, error, success
  final String text;

  static AnnouncementMessage? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final message = json['message'];
    if (message is! Map<String, dynamic>) return null;
    final show = message['show'] as bool? ?? false;
    final type = (message['type'] as String?) ?? 'info';
    final text = (message['text'] as String?) ?? '';
    return AnnouncementMessage(show: show, type: type, text: text);
  }

  static AnnouncementMessage? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>?);
    } catch (_) {
      return null;
    }
  }
}

/// سرویس اعلان: اول پنل، بعد GitHub، بعد کش. همیشه آخرین نتیجه را کش می‌کند.
class AnnouncementService {
  AnnouncementService(this._ref);
  final Ref _ref;

  Future<AnnouncementMessage?> fetch() async {
    // ۱) از پنل
    final panelUrl = _ref.read(Preferences.tikNetPanelBaseUrl);
    if (panelUrl.isNotEmpty) {
      final msg = await _fetchFromPanel(panelUrl);
      if (msg != null) {
        await _saveToCache(msg);
        return msg;
      }
    }

    // ۲) از GitHub
    final githubMsg = await _fetchFromGitHub();
    if (githubMsg != null) {
      await _saveToCache(githubMsg);
      return githubMsg;
    }

    // ۳) از کش
    return _readFromCache();
  }

  Future<AnnouncementMessage?> _fetchFromPanel(String baseUrl) async {
    final url = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _announcementTimeout,
        sendTimeout: _announcementTimeout,
        receiveTimeout: _announcementTimeout,
      ));
      final res = await dio.get<Map<String, dynamic>>('${url}api/customer/announcement');
      return AnnouncementMessage.fromJson(res.data);
    } catch (_) {
      return null;
    }
  }

  Future<AnnouncementMessage?> _fetchFromGitHub() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _announcementTimeout,
        sendTimeout: _announcementTimeout,
        receiveTimeout: _announcementTimeout,
      ));
      final res = await dio.get<Map<String, dynamic>>(_githubConfigUrl);
      final data = res.data;
      if (data == null) return null;
      final message = data['message'];
      if (message is Map<String, dynamic>) {
        return AnnouncementMessage.fromJson({'message': message});
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  AnnouncementMessage? _readFromCache() {
    final raw = _ref.read(Preferences.tikNetCachedAnnouncement);
    return AnnouncementMessage.fromJsonString(raw);
  }

  Future<void> _saveToCache(AnnouncementMessage msg) async {
    final json = {'message': {'show': msg.show, 'type': msg.type, 'text': msg.text}};
    await _ref.read(Preferences.tikNetCachedAnnouncement.notifier).update(jsonEncode(json));
  }
}

final announcementServiceProvider = Provider<AnnouncementService>((ref) => AnnouncementService(ref));

final announcementProvider = FutureProvider<AnnouncementMessage?>((ref) async {
  return ref.read(announcementServiceProvider).fetch();
});
