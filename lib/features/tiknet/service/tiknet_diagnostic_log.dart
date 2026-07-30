import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/core/model/tiknet_config.dart';
import 'package:path/path.dart' as p;

/// In-app diagnostic ring buffer + file log for TikNet support/debug.
class TikNetDiagnosticLog {
  TikNetDiagnosticLog._();

  static const _logcatTag = 'TikNetDiag';
  static const _maxLines = 1000;
  static final _buffer = <String>[];
  static File? _file;
  static bool _initialized = false;

  static void init(Directory workingDir) {
    if (!tikNetMode || _initialized) return;
    _initialized = true;
    _file = File(p.join(workingDir.path, 'tiknet_diagnostic.log'));
    try {
      if (_file!.existsSync()) {
        final tail = _file!.readAsLinesSync();
        _buffer.addAll(tail.length > 200 ? tail.sublist(tail.length - 200) : tail);
      }
    } catch (_) {}
    i('diag', 'TikNet diagnostic log started', {'path': _file?.path});
  }

  static void i(String category, String message, [Map<String, Object?>? data]) => _write('I', category, message, data);

  static void w(String category, String message, [Map<String, Object?>? data]) => _write('W', category, message, data);

  static void e(String category, String message, [Map<String, Object?>? data]) => _write('E', category, message, data);

  static void _write(String level, String category, String message, [Map<String, Object?>? data]) {
    if (!tikNetMode) return;
    final line = _format(level, category, message, data);
    _buffer.add(line);
    if (_buffer.length > _maxLines) {
      _buffer.removeRange(0, _buffer.length - _maxLines);
    }
    // Release builds are not debuggable, so `run-as` cannot reach the log file.
    // Mirroring to the platform log keeps the app diagnosable from `adb logcat`.
    developer.log(line, name: _logcatTag, level: level == 'E' ? 1000 : 800);
    final file = _file;
    if (file != null) {
      try {
        file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    }
  }

  static String _format(String level, String category, String message, [Map<String, Object?>? data]) {
    final ts = DateTime.now().toIso8601String();
    final extra = data == null || data.isEmpty ? '' : ' ${jsonEncode(_sanitize(data))}';
    return '[$ts][$level][$category] $message$extra';
  }

  static Map<String, Object?> _sanitize(Map<String, Object?> data) {
    return data.map((key, value) {
      final k = key.toLowerCase();
      if (k.contains('password') || k.contains('token') || k.contains('secret')) {
        return MapEntry(key, '***');
      }
      if (value is String && value.length > 120) {
        return MapEntry(key, '${value.substring(0, 80)}…(${value.length})');
      }
      return MapEntry(key, value);
    });
  }

  static String exportText() => _buffer.join('\n');

  static Future<String?> copyToClipboard() async {
    final text = exportText();
    if (text.isEmpty) return null;
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  static Future<void> clear() async {
    _buffer.clear();
    final file = _file;
    if (file != null && file.existsSync()) {
      await file.writeAsString('');
    }
    i('diag', 'log cleared');
  }

  static String? get filePath => _file?.path;
}
