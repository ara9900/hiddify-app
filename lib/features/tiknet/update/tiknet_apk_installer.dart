import 'dart:io';

import 'package:flutter/services.dart';

/// Installs a downloaded APK on Android via platform channel.
class TikNetApkInstaller {
  static const _channel = MethodChannel('com.hiddify.app/platform');

  static Future<void> install(String apkPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('نصب APK فقط روی اندروید پشتیبانی می‌شود');
    }
    await _channel.invokeMethod<void>('install_apk', {'path': apkPath});
  }
}
